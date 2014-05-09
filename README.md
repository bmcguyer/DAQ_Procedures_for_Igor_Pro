DAQ_Procedures_for_Igor_Pro
===========================

Procedure files to help simplify data acquisition (DAQ) in WaveMetrics Igor Pro. Includes separate files for GPIB, NIDAQmx, traditional NIDAQ, serial port, and VISA. Each file contains its own documentation. 

For example, "DAQ_GPIB.ipf" provides generic functions for managing communication with multiple devices over GPIB, using a scheme for identifying devices with strings, and provides a control panel for troubleshooting GPIB issues. Similarly, "DAQ_NIDAQmx.ipf" (and "DAQ_NIDAQ_Traditional.ipf") provide generic functions for working with NIDAQ. "DAQ_SerialPort.ipf" provides routines for using one device over a serial port (RS-232), and is currently specialized for a particular Omega temperature controller. "DAQ_VISA.ipf" provide generic functions for working with the first device detected by VISA over USB.

These files are also available as the "DAQ_Procedures" project (http://www.igorexchange.com/project/DAQ_Procedures) and as part of the "Expt_Procedures" project (http://www.igorexchange.com/project/Expt_Procedures) at Igor Exchange.
