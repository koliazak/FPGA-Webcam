# Zynq-7010 Vision

![Status: In Progress](https://img.shields.io/badge/Status-In%20Progress-orange)


This repository contains the source code, hardware design, and documentation for an edge computer vision project based on the Xilinx Zynq-7010 SoC (EBAZ4205 board). 

The goal of this project is to build a hardware-accelerated **Stereo Camera System** capable of capturing frames, detecting objects, and estimating depth. The project is divided into phases, starting with a single-camera streaming pipeline and scaling up to dual-camera stereo vision.

## Technical Specification & Project Roadmap

The development is divided into three main phases to ensure iterative progress of the Hardware/Software (HW/SW) partitioning.

### Phase 1: Minimum Viable Product (Capture & Web Streaming)

- **Goal:** Establish a reliable image capture pipeline and stream the video to a web interface.
- **Tasks:**
  - Implement mowdule in PL (FPGA) to configure the OV7670 registers.
  - Develop a pixel capture module to receive parallel data from the camera and convert it to an AXI-Stream.
  - Use DMA to write frames to DDR memory.
  - Implement a lightweight web server on the PS (ARM processor) running Petalinux to stream the frames.

### Phase 2: Hardware-Accelerated Image Processing
- **Goal:** Offload image basic computer vision tasks to the FPGA fabric.
- **Features to implement:**
  * Image enhancement (brightness/contrast adjustment, color space conversion).
  * Video stabilization.
  * Background removal / masking.
  * Basic face tracking using hardware-accelerated algorithms.

### Phase 3: Stereo Vision & Depth Estimation
- **Goal:** Synchronous capture from two cameras to calculate object distance.

## Hardware/Software Partitioning (Co-Design)

One of the core research aspects of this project is determining the optimal boundary between Programmable Logic (PL) and the Processing System (PS). 

- **Programmable Logic (FPGA):** Will handle deterministic, high-throughput operations (data ingestion, AXI-Stream conversions, low-level image processing, edge detection).
- **Processing System (ARM Core):** Will handle high-level application logic, web server, and complex CV inferences that are too heavy for the chip's logic fabric.

*(Note: The exact partitioning will be updated as experiments are conducted and performance bottlenecks are analyzed).*

## Tools & Technologies
- **HDL:** SystemVerilog / Verilog
- **Synthesis & Implementation:** Xilinx Vivado
- **Hardware:**
  - EBAZ4205 board
  - extension board 
  - 2x OV7670 camera module without FIFO
