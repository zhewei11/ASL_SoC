# AXI Multichannel Burst DMA

## Current implementation

`axi_multichannel_burst_dma` provides two fixed-function channels behind one
AXI4 master interface:

| Channel | Direction | Producer / consumer | Function |
|---:|---|---|---|
| 0 | S2MM | Ethernet L2 stream → DRAM | Write one image frame into the uncached frame buffer |
| 1 | MM2S | DRAM → CNN input stream | Read one CNN input and produce `valid/data/keep/last` |

Read and write use independent AXI channels and may progress concurrently. The
default maximum burst is 16 beats × 4 bytes = 64 bytes. A transfer is split
before an AXI 4 KiB boundary, and the final partial word is represented by byte
strobes on S2MM or `keep` on MM2S.

The configuration source is `config/asl_soc_config.json`:

```json
"dma": {
  "max_burst_beats": 16
}
```

The current CNN block is still a stub. It consumes DMA completion/checksum for
the simulated classification result; the MM2S stream interface is available for
the future real CNN datapath.

## Direct-mode versus scatter-gather

The current DMA is direct-mode: hardware receives one base address and one byte
count, completes that transfer, then reports status. This is sufficient for one
contiguous 25,600-byte image buffer.

Scatter-gather (SG) adds a descriptor-fetch engine. Software builds a descriptor
ring or linked list in memory; each descriptor normally contains source address,
destination or stream channel, length, control flags, completion status and a
next-descriptor pointer.

`Gather` means reading several non-contiguous memory regions into one output
stream. `Scatter` means distributing one input stream into several non-contiguous
memory regions.

| Property | Current direct-mode DMA | Scatter-gather DMA |
|---|---|---|
| Buffer shape | One contiguous region | Many discontiguous regions |
| CPU work | Program every transfer | Prepare a ring, then batch many transfers |
| Startup latency | Low and bounded | Descriptor fetch adds DRAM latency |
| Hardware | Two small channel state machines | Descriptor fetch, ring walker, status writer and recovery logic |
| Memory traffic | Payload only | Payload plus descriptor reads/status writes |
| Cache handling | Simple uncached buffer | Descriptors and payload ownership need explicit cache maintenance |
| Error recovery | Abort one active transfer | Must identify and retire the failed descriptor safely |
| Best fit | Fixed-size camera/CNN frames | Packet lists, fragmented buffers and queued tensor pipelines |

## Recommendation

Keep the current two-channel direct-mode burst DMA for the first complete CNN
integration. Add SG only when at least one of these becomes necessary:

- Camera or network buffers arrive as non-contiguous fragments.
- Several image buffers must be queued without one MMIO start per frame.
- CNN weights and feature maps require a scheduled chain of transfers.
- An operating system supplies page-based buffers that are not physically
  contiguous.

If SG is added, use a small on-chip descriptor prefetch FIFO and give Protocol
traffic no dependency on the descriptor path. A malformed descriptor must be
range-checked before any AXI request, and descriptor completion must be written
only after the associated payload response has completed.
