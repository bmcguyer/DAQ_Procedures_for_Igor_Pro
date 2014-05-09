#pragma rtGlobals=1		// Use modern global access method.
#pragma version = 3.0	// This File's Version	

//####[ DAQ_VISA ]######################################################
//	Bart McGuyer, Department of Physics, Princeton University 2008
//	Provides VISA initialization & communication routines.  
//	Acknowledgements:  
// -- This code comes from work performed while I was a graduate student 
//		in the research group of Professor William Happer.
//	
//	This is preliminary code to work with devices over VISA with IGOR. 
//	Right now it just sets up communication with the first discovered device 
//	connected by USB.  It should work in tandem with other DAQ files.
// In the future, it could be expanded to have the capabilities of DAQ_GPIB, 
//	since there isn't a lot of difference between the two (w.r.t. commands).
//	If you change this in the future, I recommend making it parallel DAQ_GPIB's 
//	function naming, since the functions can be swapped by substituting "gpib" for "visa".  
// 
//	Assumptions:
//	-- Igor Pro v5 and above
//	-- Wavemetrics VISA XOP installed
//	-- Only one VISA device attached by USB
//	
//	Version Notes:
//	-- v3.0: 12/2/2011 - Slight modification before posting at www.igorexchange.com.
//	-- v1.1: 9/21/2009 - Extracted this code from VISA_TDS2004B, which became Driver_TDS2004B_VISA. Reorganized and renamed things a bit.
//	
//	Notes:
//	-- No terminators are added in visaSend, but a linefeed ("\n") is expected in visaQuery. I'm not sure what are the best VISA defaults for terminators, if any.
//	-- Probably should make VISAerrormsg a static function?	
//
//	####[ Table of Contents ]####
//	Functions:						Description:
//		Init_VISA						Use to setup a session with the first available USB instrument
//		visaSend							Send a command to a device, not expecting a response.  No terminator added to message.
//		visaQuery						Send a command (with visaSend) returns string response (term = "\n").
//		closeVisa						Kills all VISA sessions, just an easier function name to remember than the actual command.
//		visa_FindAllUSB				returns instrument descriptions for all USB instruments to History.
//		VISAerrormsg					Prints a VISA error message, for use when status < 0



//visaSend:  Send a command to a device, not expecting a response.  No terminator added to message.
Function visaSend(instr, message)
	Variable instr		//VISA session
	String message		//Message to send (without terminator)
	
	VISAWrite instr, message	//Send message -- don't add any terminators, except what command calls for!!!!
End

//visaQuery:  Send a command (with visaSend) returns string response (term = "\n").
Function/S visaQuery(instr, message)
	Variable instr		//VISA session
	String message		//Message to send (without terminator)
	
	visaSend(instr, message)	//Use visaSend here to make sure termination is easy to change.
	
	VISARead/T="\n" instr, message	//Read until \n (doesn't read linefeed \n, "ascii 10", which looks like a square)
	return message
End

//Init_VISA:  Use to setup a session with the first available USB instrument
Function Init_VISA()
	//Local Variables
	Variable defaultRM=0, instr
	Variable findList=0, retcnt, status=0
	string expr = "USB?*INSTR"
	String instrDesc// = "USB0::0x0699::0x0365::C034484::INSTR"
	
	//GLOBAL Variables -- will fill these so other functions can use them later.  
	//For some reason, VISA won't take globals as inputs.
	Variable/G VISA_defaultRM=0		//global VISA session variable!
	Variable/G VISA_instr				//global session id for USB scope!
	
	VISAControl killIO	//Terminate all VISA sessions, put in nice state
	
	status = viOpenDefaultRM(defaultRM)	//Open VISA default resource manager.
	if (status < 0)
		VISAerrormsg(findList, defaultRM, status)
		abort
	endif
	
	//Finds all USB instruments, fills information about 1st detected device
	status = viFindRsrc(defaultRM, expr, findList, retcnt, instrDesc)	
	if (status < 0)
		VISAerrormsg(findList, defaultRM, status)
	endif
	if (retcnt <= 0)			
		Print "-- No USB instruments found!"
		
		VISAControl killIO	//Terminate all VISA sessions, put in nice state
		
		//GLOBALS - set to "error" values
		VISA_defaultRM = -1
		VISA_instr = -1
	else	
		//Open session with first USB device:
		viOpen(defaultRM, instrDesc, 0, 0, instr)
		
		//Get *IDN? response from device, so you know what it is...
		string dummy
		VISAWrite instr, "*IDN?" + "\r"
		VISARead/T="\r\n" instr, dummy
		
		//GLOBALS - save values for other functions to use
		VISA_defaultRM = defaultRM
		VISA_instr = instr
		
		//Print results to History:
		Print "-- VISA Setup for USB Device with description \"" + instrDesc + "\""
		Print "-- USB Device *IDN? response: \"" + dummy + "\""
		
		//Close session:
		//viClose(instr)
		
		//Leave session open for user to do tasks with device.
	endif
	
	//IGOR closes all open VISA sessions when it quits, so don't need this stuff...
	//Close all instruments
	//if (findList != 0)
	//	viClose(findList)
	//endif
	//Close VISA default resource manager
	//if (defaultRM != 0)
	//	viClose(defaultRM)
	//endif
End

//closeVisa:  Kills all VISA sessions, just an easier function name to remember than the actual command.  
Function closeVISA()
	VISAControl KillIO	//Terminate all VISA sessions, put in nice state
End

//visa_FindAllUSB:  returns instrument descriptions for all USB instruments to History.
Function VISA_FindAllUSB()
	Variable defaultRM=0, findList=0, retcnt
	String expr, instrDesc
	Variable i, status=0
	
	//Find all instruments on USB:
	do		// Just a structure to break out of in case of error
		expr = "USB?*INSTR"					//Match all USB instruments
		status = viOpenDefaultRM(defaultRM)	//Open VISA default resource manager.
		if (status < 0)
			break
		endif
		
		status = viFindRsrc(defaultRM, expr, findList, retcnt, instrDesc)	//Finds all USB instruments
		if (status < 0)
			break
		endif
		if (retcnt <= 0)
			Print "-- No USB instruments found!"
			break
		endif
		
		i = 1
		do		//Loop over all found instruments
			Printf "Instrument %d: %s\r", i, instrDesc
	
			i += 1
			if (i > retcnt)
				break
			endif
	
			status = viFindNext(findList, instrDesc)
			if (status < 0)
				break
			endif
		while(1)
	while(0)
	
	//ERROR Reporting
	if (status < 0)
		String errorDesc
		Variable viObject
	
		viObject = findList
		if (viObject == 0)
			viObject = defaultRM
		endif
	
		viStatusDesc(viObject, status, errorDesc)
		Printf "#### VISA ERROR: %s\r", errorDesc
	endif
	
	//Close all instruments
	if (findList != 0)
		viClose(findList)
	endif
	//Close VISA default resource manager
	if (defaultRM != 0)
		viClose(defaultRM)
	endif
	
	return status
End

//VISAerrormsg:  Prints a VISA error message, for use when status < 0
Function VISAerrormsg(findList, defaultRM, status)
	Variable findList, defaultRM, status
	
	String errorDesc
	Variable viObject
	
	viObject = findList
	if (viObject == 0)
		viObject = defaultRM
	endif
	
	viStatusDesc(viObject, status, errorDesc)
	Printf "#### VISA ERROR: %s\r", errorDesc
End
