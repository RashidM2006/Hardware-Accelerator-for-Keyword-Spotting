# Hardware-Accelerator-for-Keyword-Spotting
A specialized ASIC (Application-Specific Integrated Circuit) designed for Keyword Spotting (KWS). Unlike general-purpose microcontrollers that must remain fully powered to process audio, this is a "Zero-CPU" hardware accelerator that listens for a specific wake-word using a hard-wired Neural Network.

By moving the inference from software, we aim to achieve a 100x reduction in energy consumption, making it ideal for "Always-On" battery-powered devices like wearables and IoT sensors.
