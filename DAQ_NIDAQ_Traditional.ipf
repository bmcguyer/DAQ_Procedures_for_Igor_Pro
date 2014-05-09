#pragma rtGlobals=1		// Use modern global access method.
#pragma version = 3.0	// This File's Version

//####[ DAQ_NIDAQ_Traditional ]#########################################
//	Bart McGuyer, Department of Physics, Princeton University 2008
//	Provides NIDAQ initialization and communication routines.
//	Acknowledgements:  
// -- This code comes from work performed while I was a graduate student 
//		in the research group of Professor William Happer, and builds on 
//		some previous code from that group.  
//
//	Assumptions:
//	-- Igor Pro v5 and above
//	-- Wavemetrics NIDAQ Tools v1.2 (NOT Tools MX!) and above installed, which provides a NIDAQ setup menu in the Misc menu
//	-- Only one NIDAQ MX board installed (code will use the first one detected)
//	 
//	Version Notes:
//	-- v3.0: 12/2/2011 - Slight modification before posting at www.igorexchange.com.
//	-- v2.0: 9/21/2009 cleaned up code a bit.
//	
//	Notes:
//	-- Are you sure you want to use this file? This is for TRADITIONAL NIDAQ!  For NIDAQ MX, use the "DAQ_NIDAQmx" procedure file.
//		-Common functions share the same name in both files, except for Init_NIDAQ vs. Init_NIDAQmx.
// -- Currently setup for NI PCI 6052E NIDAQ board and BNC-2090 break-out box (16 channel 16 bit input +/- 10V, 2 channel 16 bit analog output +/- 10V.).  
//	
//	####[ Table of Contents ]####
//	Functions:						Description:
//		Init_NIDAQ						Set up NIDAQ interface and global variables.
//		nidaqReset						Reset the NIDAQ interface.
//		nidaqSetDacsToZero			Sets all analog outputs to zero volts (DACs).  
//		nidaqRead(channel)			Read one of the analog input channels (ACH0s)
//		nidaqSet(channel)				Set the value of an analog output channels (DACs)

// Optional: These add extra NIDAQ Tools features to Macro menu.  Good for troubleshooting NIDAQ.
//#include ":NIDAQ Procedures:NIDAQ Wave Scan Procs"		// Control Panel for reading Inputs
//#include ":NIDAQ Procedures:NIDAQ WaveForm Gen Procs"	// Control Panel for testing Outputs
//#include ":NIDAQ Procedures:NIDAQ FIFO Procs"			// Control Panel for fifo data input



//Init_NIDAQ:  Set up NIDAQ interface and global variables.
Function Init_NIDAQ()
	//  Save current data folder, setup and change to new folder root:system:NIDAQ
	String PreviousDataFolder = GetDataFolder(1);	
	NewDataFolder/O root:system;
	NewDataFolder/O/S root:system:NIDAQ;
	
	//  Setup Global Variables
	Variable/G gNIDAQNumChan = 8;			//  Number of NIDAQ input channels (output fixed at 2)
	//Make/T/O gNIDAQChanNames = {"ch0","ch1","ch2","ch3","ch4","ch5","ch6","ch7"};
	Make/T/O/N=8 gNIDAQ_InputLabels = {"ach0","ach1","ach2","ach3","ach4","ach5","ach6","ach7"};
	Make/T/O/N=2 gNIDAQ_OutputLabels = {"dac0","dac1"};
	
	//  Placeholders for channel numbers, so can use text like "ach0" to read a channel.
	//  Analog Inputs.  (Naming convention same as BNC-2090.)
	//Variable/G gNIDAQ_ach0 = 0;
	//Variable/G gNIDAQ_ach1 = 1;
	//Variable/G gNIDAQ_ach2 = 2;
	//Variable/G gNIDAQ_ach3 = 3;
	//Variable/G gNIDAQ_ach4 = 4;
	//Variable/G gNIDAQ_ach5 = 5;
	//Variable/G gNIDAQ_ach6 = 6;
	//Variable/G gNIDAQ_ach7 = 7;
	//  Analog Outputs.  (Naming convention same as BNC-2090.)
	//Variable/G gNIDAQ_dac0 = 0;
	//Variable/G gNIDAQ_dac1 = 0;
	
	//  Test if there's a board at all:  
	If(stringmatch(fNIDAQ_ListBoards(-1),""))		//  If a search for boards finds nothing
		Print "Error during Init_NIDAQ():  No NIDAQ board to setup!";
	else
		//  Now assume there's one NIDAQ board, and that it has BoardID 1.
		//  (NIDAQ Tools can only support 1 board at a time.)
		
		//  Description of settings for PCI 6025E board:  
		//  16 bit/channel, all channels, +/- 10V.
		//  Differential Mode, 8 analog inputs:  
		//    Gain per channel:  yes (previous user setting) -- E series board
		//    Has Ext Trigger:  yes (previous user setting)
		//    Has Ext Gate:  no (previous user setting)
		//    Has Ext Timebase:  yes (previous user setting)
		//    Interval Scanning OK:  yes (previous user setting)
		//    Has Ext Scan Clock:  yes (previous user setting)
		//    Mult Ext OK:  yes (previous user setting)
		//  Analog outputs, 2 channels, 16 bit.  +/- 10V.
		//  Counter/Timer Settings:
		//    Counter Type:General Purpose b/c E series (previous user setting)
		//    Possible Counter Conflict:  no (previous user setting)
		
		//Board Setup Commands (see "Configure NIDAQ..." in Misc menu for more info)
		fNIDAQ_BoardReset(1)					// Resets Board, BoardID=1
		fNIDAQ_SetInputChans(1, 8, 16, 1, 1)		// Input Options, (BoardID, # Channels, Bits/Ch, , )
		fNIDAQ_SetInputTrigger(1, 0, 1, 1, 1, 1)		// Input Options, (BoardID, , , , , )
		fNIDAQ_InputConfig(1, 0, 0, 20.000000)		// Input Range Type, (BoardID, , , 20 means +/-10V)
		fNIDAQ_SetOutputChans(1, 2, 16, 0, 0, 0)	// Output Options, (BoardID, # Channels, Bits/Ch, , , )
		fNIDAQ_OutputConfig(1, 0, 0, 10.000000)	// Output Ch 1
		fNIDAQ_OutputConfig(1, 1, 0, 10.000000)	// Output Ch 2 
		fNIDAQ_SetCounters(1, 2, 0, 0)			// Counter Type, (Board ID, 2 = general, ...)
		//NOTE:  If you change the above, make sure to update NIDAQ_ResetBoard()
		
		//  Set both analog outputs to zero volts
		fNIDAQ_WriteChan(1, 0, 0)
		fNIDAQ_WriteChan(1, 1, 0)
		
		//  Print Status to History
		Print "NIDAQ Initialized:", fNIDAQ_BoardName(1), "to BNC-2090.";
		//Print fNIDAQ_NumAnalogInputChans(1), " input channels (", fNIDAQ_InputLowV(1), "to", fNIDAQ_InputHighV(1), "V,", fNIDAQ_AnalogInputRes(1), "bits/channel)."
		//Print fNIDAQ_NumAnalogOutputChans(1), " output channels (", fNIDAQ_AnalogOutputRes(1), "bits/channel)."	
	endif
	
	//  Reset data folder to value before function call
	SetDataFolder PreviousDataFolder;
End

//nidaqReset:  Reset the NIDAQ interface.
Function nidaqReset()
	//Assumes BoardID = 1;
	fNIDAQ_BoardReset(1)					// Resets Board, BoardID=1
	fNIDAQ_SetInputChans(1, 8, 16, 1, 1)		// Input Options, (BoardID, # Channels, Bits/Ch, , )
	fNIDAQ_SetInputTrigger(1, 0, 1, 1, 1, 1)		// Input Options, (BoardID, , , , , )
	fNIDAQ_InputConfig(1, 0, 0, 20.000000)		// Input Range Type, (BoardID, , , 20 means +/-10V)
	fNIDAQ_SetOutputChans(1, 2, 16, 0, 0, 0)	// Output Options, (BoardID, # Channels, Bits/Ch, , , )
	fNIDAQ_OutputConfig(1, 0, 0, 10.000000)	// Output Ch 1
	fNIDAQ_OutputConfig(1, 1, 0, 10.000000)	// Output Ch 2 
	fNIDAQ_SetCounters(1, 2, 0, 0)			// Counter Type, (Board ID, 2 = general, ...)
	//NOTE:  Make sure these settings are the same as in Init_NIDAQ()
End

//nidaqSetDacsToZero:  Sets all analog outputs to zero volts (DACs).  
Function nidaqSetDacsToZero()
	fNIDAQ_WriteChan(1, 0, 0);
	fNIDAQ_WriteChan(1, 1, 0);
End

//nidaqRead:  Read one of the analog input channels (ACHs).
Function nidaqRead(channel)
	Variable channel;		//analog input channel ("ACH") = 0 to 7.
	
	//Return output in volts or NaN, Gain = 1.
	return fNIDAQ_ReadChan(1, channel,1)	// Assumes BoardID = 1
End

//nidaqSet:  Set the value of an analog output channels (DACs).
Function nidaqSet(channel, volts)
	Variable channel, volts;	//analog input channel ("dac") = 0 to 1. 
	
	fNIDAQ_WriteChan(1, channel, volts)	// Assumes BoardID = 1
End

