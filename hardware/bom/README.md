# Hardware inventory

[bom.csv](bom.csv) is the retained component inventory. It is not a completed procurement or assembled-hardware record.
Supplier identifiers, availability and substitutions have not been reverified. Its passive components and optional
future-interface resistors should not be mistaken for verified breakout requirements. The cable row contains historical
generic identifiers; identify the actual Micro-USB data cable used.

Required integration: Arty S7-25, INMP441 breakout, PCM5102A breakout, appropriate power/interconnects and a supported
line-output load. Headphones additionally require a verified driver. The inventory does not select that amplifier.

[Hardware status](../../docs/hardware/README.md) and [validation template](../../docs/hardware/HARDWARE_VALIDATION.md)
separate intended parts from actual assembly. No alternate microphone is declared drop-in compatible without interface
validation.
