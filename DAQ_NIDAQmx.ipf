#pragma rtGlobals=1		// Use modern global access method.
#pragma version = 3.0	// This File's Version

//####[ DAQ_NIDAQmx ]###################################################
//	Bart McGuyer, Department of Physics, Princeton University 2008
//	Provides NIDAQ initialization and communication routines.
//	Acknowledgements:  
// -- This code comes from work performed while I was a graduate student 
//		in the research group of Professor William Happer, and builds on 
//		some previous code from that group.  
//	
//	DAQ_NIDAQmx is intended to provide generic functions for working with one 
//	NIDAQ board and a BNC-2090 break-out box.  It is not intended to be device-
//	specific, or measurement specific.
//	For example:  
//		Init_NIDAQmx()
//		Print num2str(nidaqRead(0))
//	This inits NIDAQ  and prints the input voltage at ACH0.
//	
//	Assumptions:
//	-- Igor Pro v5 and above
//	-- Wavemetrics NIDAQ Tools MX v1 and above installed
//	-- Only one NIDAQ MX board installed (code will use the first one detected)
//	
//	Version Notes:
//	-- v3.0: 12/2/2011 - Slight modification before posting at www.igorexchange.com.
//	-- v2.1: 1/14/2010 - changed Init_NIDAQmx to also include pseudo-differential, which is needed for BNC-2110 break-out boxes.
//	-- 12/7/09 - cleanup incomplete wave I/O routines.
//	-- v2.0: 9/21/2009 - Changed Init_NIDAQmx() to not set DAC's to zero, which was a dangerous default behavior (ex: if using DAC to control laser...).
//	
// Possible Future Work:
//	-- Take advantage of NIDAQ's ability to send pulses and send/read waves directly?  
//	-- Could make routines to output waves, say to turn a DAC channel into a function generator.  
//	-- Generic routine to use a DAC to trigger external device, such as laser scan, and to read responses?
//
//	Notes: 
//	-- This is for NIDAQ MX!  For TRADITIONAL NIDAQ, use the "DAQ_NIDAQ_Traditional" procedure file.
//			-Common functions share the same name in both files, except for Init_NIDAQmx vs. Init_NIDAQ.
//	-- All switches must be set the same on a BNC-2090.  This is why mxChanMode is not a list.
//	-- Originally setup for PCI 6052E board with BNC-2090, DIFF mode +/- 10V.  (resolution of board is 16 bits ~ 0.3mV for +/-10V range).  
//	-- Measured speed of read/set operations with Igor's microsecond timer (startMStimer) for PCI 6052E, BNC-2090:  
//			nidaqRead takes ~ 3.4 ms	-->	3.4 ms / channel
//			nidaqFastRead ~ 1.8 ms		-->	0.23 ms / channel (did 8 at once)
//			nidaqSet ~ 2.4 ms				-->	2.4 ms / channel
//			nidaqFastSet ~ 1.2 ms		-->	0.6 ms / channel (did 2 at once)
//		So don't get the advertised 500x speedup.  Instead, get closer to 15x read and 4x set.
//  
//	####[ Table of Contents ]####
//	Functions:							Description:
//		Init_NIDAQmx						Set up NIDAQ MX interface and global variables.
//		nidaqReset							Force a hardware reset of the NIDAQ MX board.
//		nidaqSetDacsToZero			Sets all analog outputs to zero volts (DACs).  
//		nidaqRead							Read one of the analog input channels (ACH0-7)
//		nidaqSet							Set the value of an analog output channels (DAC0-1)
//		nidaqSetupFastInput			Sets up all input channels for fast read (faster than just reading a channel)
//		nidaqFastRead					Fast-read all ACH, fills passed array reference name with channel values.
//		nidaqStopFastInput			Stops fast read of ACH channels.
//		nidaqSetupFastOutput			Inits DAC's to 0 and sets up all output channels for fast read (faster than just setting a channel)
//		nidaqFastSet						Fast-set all DAC, using values in passed array name reference
//		nidaqStopFastOutput			Sets DAC's to 0, stops fast setting of DACs.
//		nidaqGrabWave		  			Acquires analog data from one channel into a new wave with the desired name, length, and time between points
//	Static Functions:
//		nidaqMode  						Return mode string based on ChanMode setting, for Nidaq calls

// Here are extra NIDAQ Tools MX features you can load, which are good for troubleshooting:
//#include <NIDAQmxWaveScanProcs>			//Adds controls Data > NIDAQ Tools MX > Wave Scan Controls
//#include <NIDAQmxWaveFormGenProcs>	//Adds controls Data > NIDAQ Tools MX > Waveform Generator
//#include <NIDAQmxFIFOProcs>
//#include <NIDAQmxFIFOReviewProcs>
//#include <NIDAQmxRepeatedScanProcs>
//#include <NIDAQmxPulseTrainGenerator>
//#include <NIDAQmxSimpleEventCounter>



//######################################################################
// Static Variables					(allow easy dynamic changes of code, but ONLY work for functions - not Macros!)
Static strconstant ksNIDAQmxPath = "root:System:NIDAQmx"		//NIDAQ MX data folder location
Static strconstant ksNIDAQmxPathParent = "root:System"			//Parent folder of data folder location



//######################################################################
//	NIDAQ MX Routines

//Init_NIDAQmx:  Set up NIDAQ MX interface and global variables.
Function Init_NIDAQmx()
	// Change to NIDAQ MX data folder
	String PreviousDataFolder = GetDataFolder(1)	//Save previous data folder
	NewDataFolder/O/S $ksNIDAQmxPathParent			//Make sure parent folder exists
	NewDataFolder/O/S $ksNIDAQmxPath					//Change to NIDAQ MX data folder
	
	//  Global Variables for NIDAQ MX Functionality
	String/G mxDevName;							// Placeholder for the board name
	Variable/G mxChanMode = 0;				//  Switch setting on breakout box.  Usually 0 (Diff) for BNC-2090 or 3 (PDIFF) for BNC-2110. 
	//		Note: all switches must be set the same on BNC-2090.  0 = Diff (8 inputs), 1 = RSE, 2 = NRSE, 3 = P-Diff (don't use), -1 = default (don't use!) 
	Variable/G mxNumChan;						//  Number of NIDAQ input channels ("ACH", either 8 or 16)
	Variable/G mxNumDAC = 2;					//  Number of NIDAQ output channels ("DAC", fixed at 2)

	// Max and Min Voltages for each channel (go ahead and set for all 16 possible channels, so don't have to resize)
	//		Note:  Should be able to set Max and Min V individually for each ACH and DAC, if desired.  
	Make/O/N=16 mxChanMaxV = {10,10,10,10,	10,10,10,10,	10,10,10,10,	10,10,10,10}
	Make/O/N=16 mxChanMinV = {-10,-10,-10,-10,	-10,-10,-10,-10,	-10,-10,-10,-10,	-10,-10,-10,-10}
	Make/O/N=2 mxDacMaxV = {10,10}			// Max Voltage for each DAC
	Make/O/N=2 mxDacMinV = {-10,-10}		// Min Voltage for each DAC
	
	//Set mxNumChan based on mxChanMode
	string mode			//Used to display test of mode when printing status later
	switch(mxChanMode)
		case 0://DIFF mode
			mxNumChan = 8
			mode = "DIFF"
			break
		case 1:	//RSE mode
			mxNumChan = 16
			mode = "RSE"
			break
		case 2://NRSE mode
			mxNumChan = 16
			mode = "NRSE"
			break
		case 2://Pseudo-Differential mode
			mxNumChan = 8
			mode = "PDIFF"
			break
		default://invalid modes: default (-1) or other.
			//Disable all channels
			mxNumChan = 0
			//Print error message
			Print "#### ERROR during Init_NIDAQmx: Invalid Mode = " + num2str(mxChanMode) + "!  ACH0-7 disabled."
			abort
	endswitch
	
	//  Collect name of first board from list of all active board names
	mxDevName = StringFromList(0,fDAQmx_DeviceNames());
	
	If(stringmatch(mxDevName,""))		
		//  If there are NO active boards, quit with error message
		Print "#### ERROR during Init_NIDAQmx():  No NIDAQ MX board(s) to setup!";
	else
		//  Hooray, Board(s) Found!  Assume we are going to work with the first board ONLY!
		fDAQmx_ResetDevice(mxDevName)		//  Do a hardware reset of the board
		//nidaqSetDacsToZero()					//  WARNING!  Set both analog outputs to zero volts -- DISABLED b/c potentially dangerous default behavior!
		
		//  Print Status to History
		Print "-- NIDAQmx Initialized:  Board  = " + mxDevName+ ", Mode = " + mode + "."//", DAC0 & DAC1 set to 0V."
		//Print num2str(mxNumChan) + " Inputs, " + num2str(mxNumDac) + " Outputs"
		//Print "Last Cal. " + Secs2Date(fDAQmx_SelfCalDate(mxDevName),0) + ", Orig. Cal. " + Secs2Date(fDAQmx_ExternalCalDate(mxDevName),0)
	endif
	
	SetDataFolder PreviousDataFolder		// Reset data folder to value before function call
End

//nidaqReset:  Force a hardware reset of the NIDAQ MX board.
Function nidaqReset()
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	fDAQmx_ResetDevice(DevName)
End

//nidaqSetDacsToZero:  Sets all analog outputs to zero volts (DACs).  
Function nidaqSetDacsToZero()
	NVAR mxNumDAC = $(ksNIDAQmxPath + ":mxNumDAC")
	
	variable ii
	for(ii = 0; ii < mxNumDAC; ii += 1)
		nidaqSet(ii,0.0)
	endfor
End

//nidaqRead:  Read one of the analog input channels (ACH0-7)
Function nidaqRead(channel)
	Variable channel;		//analog input channel ("ACH") = 0 to 7.
	
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR ChanMode = $(ksNIDAQmxPath + ":mxChanMode")
	NVAR NumChan = $(ksNIDAQmxPath + ":mxNumChan")
	WAVE MinV = $(ksNIDAQmxPath + ":mxChanMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxChanMaxV")
	
	//Test if channel index is allowed
	if((channel >= 0)&&(channel < NumChan))
		// Read ACH channel with appropriate settings
		Variable value = fDAQmx_ReadChan(DevName,channel,MinV[channel],MaxV[channel],ChanMode)
		
		// Test for error
		If(numtype(value)==0)
			return value;		//No Error
		else
			Print "#### ERROR during nidaqRead():  Value is NaN!"
			print fDAQmx_ErrorString();
			return NaN;
		endif
	else
		Print "#### ERROR during nidaqRead(): Channel = " + num2str(channel) + " is out of range!"
		return NaN;
	endif
End

//nidaqSet:  Set the value of an analog output channels (DAC0-1)
Function nidaqSet(channel, volts)
	Variable channel, volts;	//analog input channel ("dac") = 0 to 1. 
	
	//Global Variables for allowed channels, voltage limits
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumDac = $(ksNIDAQmxPath + ":mxNumDac")
	WAVE MinV = $(ksNIDAQmxPath + ":mxDacMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxDacMaxV")
	
	//Test if channel index is allowed
	if((channel >= 0)&&(channel < NumDac))
		//  Set DAC channel with appropriate settings
		fDAQmx_WriteChan(DevName,channel,volts,MinV[channel],MaxV[channel])
	else
		Print "#### ERROR during nidaqSet(): Channel = " + num2str(channel) + " is out of range!"
	endif
End



//######################################################################
//	Fast Read and Set Operations

//nidaqSetupFastInput:  Sets up all input channels for fast read (~ 500x faster than just reading a channel)
Function nidaqSetupFastInput()
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumChan = $(ksNIDAQmxPath + ":mxNumChan")
	WAVE MinV = $(ksNIDAQmxPath + ":mxChanMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxChanMaxV")
	
	string param = ""
	variable ii
	
	//Loop over channels to construct parameter string
	for(ii = 0; ii < NumChan; ii += 1)
		param += num2istr(ii) + nidaqMode() + "," + num2istr(MinV[ii]) + "," + num2istr(MaxV[ii]) + ";"	//Don't use spaces!
	endfor
	
	DAQmx_AI_SetupReader/DEV=DevName param		//Sets up fast read of all ACH channels.
End


//nidaqFastRead:  Fast-read all ACH, fills passed array name with channel values.
//NOTE:  Could merge this with nidaqRead, using binary flag for fast status?  
Function nidaqFastRead(arrayName)
	string arrayName		//Name of array to fill.  needs to be as big as NumChan
	
	WAVE array = $arrayName		//Reference to array to fill with data.  
	array = NaN						//ERROR CATCH:  if fast read isn't setup, it will not modify the array.  This makes sure this error is obvious to user.  
	
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumChan = $(ksNIDAQmxPath + ":mxNumChan")
	
	if((WaveExists(array)) && (numpnts(array) == NumChan))
		//Everything checks out - fill array with ACH values.
		fDAQmx_AI_GetReader(DevName, array)
	else
		Print "#### ERROR during nidaqFastRead():  Problem with data array!"
	endif
End

//nidaqStopFastInput:  Stops fast read of ACH channels.
Function nidaqStopFastInput()
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	fDAQmx_ScanStop(DevName)
End

//nidaqSetupFastOutput:  Inits DAC's to 0 and sets up all output channels for fast read (~ 500x faster than just setting a channel)
Function nidaqSetupFastOutput()
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumDAC = $(ksNIDAQmxPath + ":mxNumDAC")
	WAVE MinV = $(ksNIDAQmxPath + ":mxDacMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxDacMaxV")
	
	string param = ""
	variable ii
	
	//Loop over channels to construct parameter string:  "output, channel, minV, maxV;"
	for(ii = 0; ii < NumDAC; ii += 1)
		param += "0, " + num2istr(ii) + "," + num2istr(MinV[ii]) + "," + num2istr(MaxV[ii]) + ";"	//Don't use spaces!
	endfor
	
	DAQmx_AO_SetOutputs/DEV=DevName/KEEP=1 param		//Sets up fast output of all DAC channels.
End

//nidaqFastSet:  Fast-set all DAC, using values in passed array name reference
//NOTE:  Could merge this with nidaqSet, using binary flag for fast status?  
Function nidaqFastSet(arrayName)
	string arrayName		//name of array of values to set as outputs of DAC's.
	
	WAVE array = $arrayName
	
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumDAC = $(ksNIDAQmxPath + ":mxNumDAC")
	
	if((WaveExists(array)) && (numpnts(array) == NumDAC))
		//Everything checks out - fill array with ACH values.
		fDAQmx_AO_UpdateOutputs(DevName, array)
	else
		Print "#### ERROR during nidaqFastSet():  Problem with data array!"
	endif
End

//nidaqStopFastOutput:  Sets DAC's to 0, stops fast setting of DACs.
Function nidaqStopFastOutput()
	//NOTE:  There's are two alternate ways to do this:  
	//(1) fDAQmx_WaveformStop(DevName)		//Unknown final DAC states!
	//(2) DAQmx_A0_UpdateOutputs/KEEP=0 "0,0;0,1"	//Known final DAC states!
	
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumDAC = $(ksNIDAQmxPath + ":mxNumDAC")
	WAVE MinV = $(ksNIDAQmxPath + ":mxDacMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxDacMaxV")
	
	string param = ""
	variable ii
	
	//Loop over channels to construct parameter string:  "output, channel, minV, maxV;"
	for(ii = 0; ii < NumDAC; ii += 1)
		param += "0, " + num2istr(ii) + "," + num2istr(MinV[ii]) + "," + num2istr(MaxV[ii]) + ";"	//Don't use spaces!
	endfor
	
	DAQmx_AO_SetOutputs/DEV=DevName/KEEP=0 param		//Sets up fast output of all DAC channels.
End

//nidaqGrabWave:  Acquires analog data from one channel into a new wave with the desired name, length, and time between points
Function nidaqGrabWave(datawave, channel, numpts, delay)
	string datawave		//name of wave to create to store data.  
	variable channel	//channel number to read
	variable numpts		//number of points to read
	variable delay		//delay between points in seconds
	
	//Global Variables for allowed channels, voltage limits, mode
	SVAR DevName = $(ksNIDAQmxPath + ":mxDevName")
	NVAR NumChan = $(ksNIDAQmxPath + ":mxNumChan")
	WAVE MinV = $(ksNIDAQmxPath + ":mxDacMinV")
	WAVE MaxV = $(ksNIDAQmxPath + ":mxDacMaxV")
	
	//Error check:
	If((stringmatch(datawave, "")) || (delay <= 0) || (numpts <= 1) || (channel < 0) || (channel >= NumChan))
		Print "#### ERROR during nidaqGrabWave():  Invalid input parameter!"
		return 0	//polite abort
	Endif
	
	//Make data wave, who's x-scaling sets the scan parameters (MX feature)
	Make/O/D/N=(numpts) $datawave = NaN
	WAVE w = $datawave
	SetScale/P x, 0, delay, "s", w
	
	//Data Acquisition:  IGOR will halt till done
	string dummy = "" + PossiblyQuoteName(datawave) + ", " + num2istr(channel) + nidaqMode() + ", " + num2istr(MinV[channel]) + ", " + num2istr(MaxV[channel]) + ";"
//	string dummy = "" + PossiblyQuoteName(datawave) + ", " + num2istr(channel) + nidaqMode() + ",  -1,  1;"
	DAQmx_Scan/DEV=DevName WAVES=dummy
End


//######################################################################
//	Static Functions

//nidaqMode:  Return mode string based on ChanMode setting, for Nidaq calls
static Function/S nidaqMode()
	NVAR ChanMode = $(ksNIDAQmxPath + ":mxChanMode")
	
	//Return mode string based on ChanMode setting
	switch(ChanMode)
		case 0://DIFF mode
			return "/DIFF"
			break
		case 1:	//RSE mode
			return "/RSE"
			break
		case 2://NRSE mode
			return "/NRSE"
			break
		default://invalid modes: (-1) or pseudo-differential (3)
			//Print error message and abort
			Print "#### Error during nidaqMode(): Invalid Mode = " + num2str(ChanMode) + "!"
			abort
			//return ""
	endswitch
End

