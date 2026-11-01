// Frame-atomic spectral gains, conjugate-bin mapping, saturating Q14 arithmetic.
`default_nettype none
`timescale 1ns / 1ps

module spectral_proc import auris_pkg::*; #(
    parameter int unsigned N_BINS = GAIN_TABLE_DEPTH,
    parameter int unsigned DATA_W = FFT_DATA_W,
    parameter int unsigned ADDR_W = $clog2(GAIN_TABLE_DEPTH)
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    // Streaming complex data from FFT
    input  wire [DATA_W-1:0]       in_re_i,
    input  wire [DATA_W-1:0]       in_im_i,
    input  wire                    in_v_i,
    input  wire                    in_last_i,
    input  wire [7:0]              fft_exponent_i, // X_stored = X / 2^E

    // Streaming complex data to IFFT
    output logic [DATA_W-1:0]      out_re_o,
    output logic [DATA_W-1:0]      out_im_o,
    output logic                   out_v_o,
    output logic                   out_last_o,

    // Control inputs (Q2.14, 16-bit)
    input  wire [1:0]              mode_i,
    input  wire [DATA_W-1:0]       master_gain_i,
    input  wire [DATA_W-1:0]       noise_floor_i,
    input  wire [DATA_W-1:0]       gate_ratio_i,

    // Gain-table write interface
    input  wire [ADDR_W-1:0]       bin_addr_i,
    input  wire [DATA_W-1:0]       bin_wdata_i,
    input  wire                    bin_we_i,
    input  wire [1:0]              bin_bank_i,
    input  wire                    bank_commit_i,
    output wire                    bank_active_o
);

    // -------------------------------------------------------------------------
    // Dual-bank gain table
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_W-1:0] gain_bank_a [0:N_BINS-1];
    (* ram_style = "block" *) logic [DATA_W-1:0] gain_bank_b [0:N_BINS-1];

    initial begin
        for (int i = 0; i < N_BINS; i++) begin
            gain_bank_a[i] = UNITY_GAIN_Q14;
            gain_bank_b[i] = UNITY_GAIN_Q14;
        end
    end

    // A commit requests ownership transfer; only the first accepted bin
    // changes the bank. The loader must wait for bank_active_o before reuse.
    logic active_bank, pending_bank, pending_commit;
    logic [7:0] bin_idx;
    logic [15:0] frame_master, frame_noise, frame_ratio;
    logic [7:0] frame_exponent, exponent_s1, exponent_s2, exponent_s3;
    wire first_bin = (bin_idx == 0);
    wire selected_bank = first_bin ?
        (bank_commit_i ? bin_bank_i[0] : (pending_commit ? pending_bank : active_bank)) : active_bank;
    wire [7:0] mirrored_bin = (bin_idx > 128) ? (8'd0-bin_idx) : bin_idx;
    // The 128-word interface has no Nyquist word: explicitly extend bin 127.
    wire [6:0] gain_address = (mirrored_bin == 128) ? 7'd127 : mirrored_bin[6:0];
    assign bank_active_o = active_bank;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_bank <= 0; pending_bank <= 0; pending_commit <= 0;
            bin_idx <= 0;
            frame_master <= 16384; frame_noise <= 0; frame_ratio <= 16384;
            frame_exponent <= 0;
        end else begin
            if (bank_commit_i) begin
                pending_bank <= bin_bank_i[0];
                pending_commit <= 1;
            end
            if (in_v_i) begin
                bin_idx <= bin_idx + 1'b1;
                if (first_bin) begin
                    active_bank <= selected_bank;
                    pending_commit <= 0;
                    frame_master <= master_gain_i;
                    frame_noise <= noise_floor_i;
                    frame_ratio <= gate_ratio_i;
                    frame_exponent <= fft_exponent_i;
                end
            end
        end
    end
    always_ff @(posedge clk_i) begin
        if (rst_n_i && bin_we_i && bin_bank_i[0] != active_bank) begin
            if (!bin_bank_i[0]) gain_bank_a[bin_addr_i] <= bin_wdata_i;
            else gain_bank_b[bin_addr_i] <= bin_wdata_i;
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk_i) if (rst_n_i) begin
        if (bin_we_i && bin_bank_i[0] == active_bank)
            $fatal(1, "Gain loader attempted to overwrite the active bank");
        if (in_v_i && ($isunknown(fft_exponent_i) || fft_exponent_i > 16))
            $fatal(1, "Unsupported or unknown FFT exponent");
        if (in_v_i && in_last_i != (bin_idx == 255))
            $fatal(1, "Spectral frame marker mismatch");
    end
`endif

    // -------------------------------------------------------------------------
    // Pipeline stage 1: read gain from active bank
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] gain_s1;
    logic [DATA_W-1:0] in_re_s1, in_im_s1;
    logic              in_v_s1,  in_last_s1;
    logic [15:0] master_s1, noise_s1, ratio_s1;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            gain_s1    <= '0;
            in_re_s1   <= '0;
            in_im_s1   <= '0;
            in_v_s1    <= 1'b0;
            in_last_s1 <= 1'b0;
            master_s1 <= '0;
            noise_s1 <= '0;
            ratio_s1 <= '0;
            exponent_s1 <= 0;
        end else begin
            if (selected_bank == 1'b0) gain_s1 <= gain_bank_a[gain_address];
            else                     gain_s1 <= gain_bank_b[gain_address];
            in_re_s1   <= in_re_i;
            in_im_s1   <= in_im_i;
            in_v_s1    <= in_v_i;
            in_last_s1 <= in_last_i;
            master_s1 <= first_bin ? master_gain_i : frame_master;
            noise_s1 <= first_bin ? noise_floor_i : frame_noise;
            ratio_s1 <= first_bin ? gate_ratio_i : frame_ratio;
            exponent_s1 <= first_bin ? fft_exponent_i : frame_exponent;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 2: effective_gain = gain_s1 * master_gain_i (Q2.14)
    // -------------------------------------------------------------------------
    logic [17:0]             eff_gain_s2;
    logic [15:0]             noise_s2, ratio_s2;
    logic [DATA_W-1:0]        in_re_s2, in_im_s2;
    logic                     in_v_s2,  in_last_s2;
    logic [31:0]              eff_mul;

    assign eff_mul = gain_s1 * master_s1;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            eff_gain_s2 <= '0;
            in_re_s2    <= '0;
            in_im_s2    <= '0;
            in_v_s2     <= 1'b0;
            in_last_s2  <= 1'b0;
            noise_s2 <= '0;
            ratio_s2 <= '0;
            exponent_s2 <= 0;
        end else begin
            eff_gain_s2 <= eff_mul[31:14];
            noise_s2 <= noise_s1;
            ratio_s2 <= ratio_s1;
            exponent_s2 <= exponent_s1;
            in_re_s2    <= in_re_s1;
            in_im_s2    <= in_im_s1;
            in_v_s2     <= in_v_s1;
            in_last_s2  <= in_last_s1;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 3: compute |X|^2 = re^2 + im^2
    // -------------------------------------------------------------------------
    logic [31:0] mag_sq_s3;
    logic [17:0]             eff_gain_s3;
    logic [19:0]             attenuated_gain_s3;
    wire [33:0] gate_product = eff_gain_s2 * ratio_s2;
    logic [DATA_W-1:0]        noise_floor_s3;
    logic [DATA_W-1:0]        in_re_s3, in_im_s3;
    logic                     in_v_s3,  in_last_s3;
    logic signed [31:0]       re_sq, im_sq;

    assign re_sq = $signed(in_re_s2) * $signed(in_re_s2);
    assign im_sq = $signed(in_im_s2) * $signed(in_im_s2);

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mag_sq_s3   <= '0;
            eff_gain_s3 <= '0;
            noise_floor_s3 <= '0;
            exponent_s3 <= 0;
            attenuated_gain_s3 <= '0;
            in_re_s3    <= '0;
            in_im_s3    <= '0;
            in_v_s3     <= 1'b0;
            in_last_s3  <= 1'b0;
        end else begin
            mag_sq_s3   <= re_sq + im_sq;
            eff_gain_s3 <= eff_gain_s2;
            noise_floor_s3 <= noise_s2;
            exponent_s3 <= exponent_s2;
            attenuated_gain_s3 <= gate_product[33:14];
            in_re_s3    <= in_re_s2;
            in_im_s3    <= in_im_s2;
            in_v_s3     <= in_v_s2;
            in_last_s3  <= in_last_s2;
        end
    end

    // -------------------------------------------------------------------------
    // Stages 4..7 isolate restoration, gate selection, multiply and saturation.
    // Seven registered stages total; throughput remains one bin per clock.
    // Valid and last follow the same registers as their complex sample.
    // -------------------------------------------------------------------------
    logic [63:0] restored_power_s4, threshold_power_s4;
    logic [17:0] eff_gain_s4;
    logic [19:0] attenuated_gain_s4, gated_gain_s5;
    logic [DATA_W-1:0] in_re_s4, in_im_s4, in_re_s5, in_im_s5;
    logic in_v_s4, in_last_s4, in_v_s5, in_last_s5;
    logic in_v_s6, in_last_s6;
    logic signed [36:0] mul_re_s6, mul_im_s6;

    // Q2.14 power of X/256: preserve the original full-width comparison
    // without rounding. Supported E<=16 fits the restored power in 64 bits.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            restored_power_s4 <= '0; threshold_power_s4 <= '0;
            eff_gain_s4 <= '0; attenuated_gain_s4 <= '0;
            in_re_s4 <= '0; in_im_s4 <= '0;
            in_v_s4 <= 1'b0; in_last_s4 <= 1'b0;
        end else begin
            restored_power_s4 <= {32'b0, mag_sq_s3} << (2 * exponent_s3);
            threshold_power_s4 <= {18'b0, noise_floor_s3, 30'b0};
            eff_gain_s4 <= eff_gain_s3;
            attenuated_gain_s4 <= attenuated_gain_s3;
            in_re_s4 <= in_re_s3; in_im_s4 <= in_im_s3;
            in_v_s4 <= in_v_s3; in_last_s4 <= in_last_s3;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            gated_gain_s5 <= '0;
            in_re_s5 <= '0; in_im_s5 <= '0;
            in_v_s5 <= 1'b0; in_last_s5 <= 1'b0;
        end else begin
            gated_gain_s5 <= (restored_power_s4 < threshold_power_s4)
                ? attenuated_gain_s4 : {2'b0, eff_gain_s4};
            in_re_s5 <= in_re_s4; in_im_s5 <= in_im_s4;
            in_v_s5 <= in_v_s4; in_last_s5 <= in_last_s4;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mul_re_s6 <= '0; mul_im_s6 <= '0;
            in_v_s6 <= 1'b0; in_last_s6 <= 1'b0;
        end else begin
            mul_re_s6 <= $signed(in_re_s5) * $signed({1'b0, gated_gain_s5});
            mul_im_s6 <= $signed(in_im_s5) * $signed({1'b0, gated_gain_s5});
            in_v_s6 <= in_v_s5; in_last_s6 <= in_last_s5;
        end
    end

    function automatic logic [15:0] saturate_q14(input logic signed [36:0] product);
        logic signed [36:0] scaled;
        begin
            scaled = product >>> 14;
            if (scaled > 32767) return 16'h7fff;
            else if (scaled < -32768) return 16'h8000;
            else return scaled[15:0];
        end
    endfunction

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_re_o  <= '0;
            out_im_o  <= '0;
            out_v_o   <= 1'b0;
            out_last_o<= 1'b0;
        end else begin
            out_re_o  <= saturate_q14(mul_re_s6);
            out_im_o  <= saturate_q14(mul_im_s6);
            out_v_o   <= in_v_s6;
            out_last_o<= in_last_s6;
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (N_BINS != 128 || DATA_W != 16 || ADDR_W != 7)
            $fatal(1, "spectral_proc supports N_BINS=128 DATA_W=16 ADDR_W=7");
    end

endmodule : spectral_proc

`default_nettype wire
