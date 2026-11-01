# STATUS2 audio error indication

STATUS2 now latches on clipping **or dropped audio**: RX CDC pair rejected,
TX CDC pair rejected, or an incoming output-buffer block rejected because both
halves are occupied. Reset clears the sticky indicators. The LED does not
identify the category; internal signals `rx_drop_dsp`, `tx_drop_sticky`, and
`dsp_error_flags[4]` distinguish these cases in simulation/debug.

RX admission is atomic: both channel FIFOs must have space. TX admission already
uses the same paired policy. A rejection discards one stereo pair rather than
allowing the channels to diverge. Output-buffer overflow discards a whole block.
