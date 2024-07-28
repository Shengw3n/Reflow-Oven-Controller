# Reflow Oven Controller Project

## Introduction

This project involves the design, construction, programming, and testing of a Reflow Oven Controller using a a 1T-8051 based series MCU. The Reflow Oven Controller is used for assembling surface mount devices (SMDs) onto printed circuit boards (PCBs) through the process of reflow soldering. This process utilizes a K-type thermocouple for temperature measurement and an LCD for displaying relevant information. The project also includes additional functionalities such as user interface buttons, automatic cycle termination on error, temperature strip chart plotting, and email notifications.

![project1](https://github.com/user-attachments/assets/12cdd429-9bf4-4b84-85cf-1b1af16114ab)

## Project Details

### Hardware Components
- **Microcontroller**: N76E003
- **LCD Controller**: HD44780
- **Temperature Sensor**: K-type Thermocouple
- **Push Buttons**: 6
- **Op-Amp**: OP07
- **Charge Pump Voltage Converter**: TC7660S
- **Solid State Relay Box**
- **N-channel MOSFET**: 13N06LS
- **Resistors**: 100kΩ and 270Ω

### Software Features
- Programmed in assembly language
- Capable of measuring temperatures between 25°C and 240°C
- Operate a 1500W toaster oven using a solid state relay
- Aborts the reflow process if the oven doesn't reach at least 50°C in the first 60 seconds of operation.
- Selectable reflow profile parameters such as soak temperature, soak time, reflow temperature, and reflow time
- LCD display showing temperature, running time, and current reflow state
- Start/Stop functionality via pushbuttons
- Automatic cycle termination on error
- Real-time temperature strip chart plotting
- Email notifications for various heating stages
- Audio reminders for cycle completions
- Temperature readings in Celsius and Fahrenheit (validated with an error margin of ±3°C)

## Video Demonstration
Here is a video showcasing the Reflow Oven Controller in action:
[[[![Reflow Oven Controller Video](./video_thumbnail.jpg)](./project_demo.mp4)](https://github.com/Shengw3n/Reflow-Oven-Controller)](https://www.youtube.com/watch?v=fH3kwNQ_S6Q)
