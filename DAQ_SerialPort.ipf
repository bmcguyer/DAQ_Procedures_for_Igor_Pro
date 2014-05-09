#pragma rtGlobals=1		// Use modern global access method.
#pragma version = 3.0	// DAQ_SerialPort version

//####[ DAQ_SerialPort ]################################################
//	Bart McGuyer, Department of Physics, Princeton University 2008
//	Provides Serial Port initialization and communication routines to 
// control one device on one serial port (RS-232).
//	Acknowledgements: 
// -- This code comes from work performed while I was a graduate student 
//		in the research group of Professor William Happer.  
//	
//	DAQ_SerialPort is intended to provide generic functions for using one serial port.
//	Due to the nature of RS-232, only one device can be controlled at a time.  Thus 
//	this procedure file is partly specialized for the device currently being controlled.
//	
//	CURRENT SETUP:
//	RS-232 over COM1 to Omega CN8561-RTD-T1-C2 Temperature Controller.
//		Controller ID set to 04, baud = "24.o.7".
//		Format of commands to Omega CN8561:  "#" + Controller ID (ex: "04") + message, may have comma + "\r\n".
//		Format of responses from Omega CN8561:  "\n" + message, may have comma + "\r\n".
//
//	Assumptions:
//	-- Igor Pro v5 and above
//	-- Wavemetrics VDT2 XOP installed
//	
//	Version Notes:
//	-- v3.0: 12/2/2011 - Slight modification before posting at www.igorexchange.com.
//	-- v2.0: 9/21/2009 - Cleaned up code a bit.
//	
//	Notes:  
//	-- Configured to open COM1 for now (choices usually are COM1-4, Printer, or Modem).
//	-- VDT2 should automatically closes all open serial ports when IGOR quits.
//
//	####[ Table of Contents ]####
//	Functions:						Description:
//		Init_SerialPort				initializes serial port communication
//		serialportClear				clears/resets serial port interface
//		serialportSend					sends msg via operations port
//		serialportRead					returns string response via the operations port
//		serialportQuery				queries operations port (transmit msg, return single response string)
//	------------------------
//		printTemp						prints current oven temperature (PV) in celsius
//		getTemp							returns current oven temperature (PV) in celsius
//		setTemp							sets the desired oven temperature (SV) in celsius
//		disableHeater					disables the heater
//		enableHeater					enables the heater
//		TempControllerVersion		prints the temperature controller version
//		printOvenStatus				prints some information about the controller's status (for testing)



//Init_SerialPort:  initializes serial port communication
Function Init_SerialPort()
	// Opens COM1 as operations port for Omega CN8561RTD-T1-C2, baud = "24.0.7" (settings from old Happer code)
	VDT2/P=COM1 baud=2400,stopbits=2,databits=7,parity=1,echo=0,terminalEOL=0,port=0,buffer=128
	//VDTOpenPort2 COM1			//Open the port, if not already open.  Not really necessary; VDT2 handles automatically.
	VDT2 killio						//Clear serial port before use.
	
	//Print Status to History
	Print "-- COM1 Initialized:  Temperature Control (Omega CN8561RTD-T1-C2)."
End

//serialportClear:  clears/resets serial port interface
Function serialportClear()
	VDT2 killio
End

//serialportSend:  sends msg via operations port
Function serialportSend(msg)
	String msg
	
	// Optional Clear Port:
	//SerialPort_Clear()
	
	VDTWrite2/O=3 msg + "\r\n"		//Timeout set to 3 seconds by /O=3
	
	// Shortest Delay Possible where back-to-back commands still work.
	//Sleep/T 10						//Wait 1/6s
End

//serialportRead:  returns string response via the operations port
Function/S serialportRead()
	String msg
	
	VDTRead2/O=3/T="\r" msg			//Timeout set to 3 seconds by /O=3
	msg = ReplaceString("\n",msg,"")	//Get rid of linefeed at start of message:
	return msg
End

//serialportQuery:  queries operations port (transmit msg, return single response string)
Function/S serialportQuery(msg)
	String msg
	
	serialportSend(msg)
	return serialportRead()
End


//####################################################################
// Functions Specific to Temperature Controller:  

//printTemp:  prints current oven temperature (PV) in celsius
Function printTemp()
	Print "-- Current Oven Temperature: " + serialportQuery("#04R00")[8,13]
End

//getTemp:  returns current oven temperature (PV) in celsius
Function getTemp()
	return str2num(serialportQuery("#04R00")[8,12])
End

//setTemp:  sets the desired oven temperature (SV) in celsius
Function setTemp(temp)
	variable temp
	string dummy
	
	// Restrict oven temperature between 0.0 and 232.2 C, which are the controller's limits
	If((temp >= 0.0)&&(temp <= 232.2))
		sprintf dummy, "%#.1f", temp;
		
		// Send command to change temperature setpoint
		serialportSend("#04M01 " + dummy + "C");
		
		// Optional Clear Port:
		//SerialPort_Clear();
	else
		Print "#### ERROR during setTemp:  Desired temperature out of range!"
	endif
End

//disableHeater:  disables the heater
Function disableHeater()
	serialportSend("#04N0");
	Print "-- Oven Temperature Controller set to STANDBY.  Heater is DISABLED."
End

//enableHeater:  enables the heater
Function enableHeater()
	serialportSend("#04F0");
	Print "-- Oven Temperature Controller ON.  Heater is ENABLED."
End

//TempControllerVersion:  prints the temperature controller version
Function TempControllerVersion()
	Print "-- Temperature Controller Version: " + serialportQuery("#04?9")[3,15]
End

//printOvenStatus:  prints some information about the controller's status (for testing)
Function printOvenStatus()
	Print "-- Oven Status:";
	Print "\tPV = " + serialportQuery("#04R00")[8,13]	//Process Value
	sleep/S 0.1
	Print "\tSV = " + serialportQuery("#04R01")[8,13]		//Setpoint Value
	
	string dummy;
	sleep/S 0.1
	
	// Check Standby:
	dummy = serialportQuery("#04?0")
	If(stringmatch(dummy[3],"F"))
		//Print "Standby = OFF"
	else
		Print "\tStandby = ON"
	endif
	
	sleep/S 0.1
	
	//Check Autotune:
	dummy = serialportQuery("#04?1")
	If(stringmatch(dummy[3],"F"))
		//Print "Autotune = OFF"
	else
		Print "\tAutotune = ON"
	endif
	
	sleep/S 0.1
	
	//Check Manual:
	dummy = serialportQuery("#04?2")
	If(stringmatch(dummy[3],"F"))
		//Print "Manual = OFF"
	else
		Print "\tManual = ON"
	endif
	
	sleep/S 0.1
	
	//Check Ramp:
	dummy = serialportQuery("#04?3")
	If(stringmatch(dummy[3],"F"))
		//Print "Ramp = OFF"
	else
		Print "\tRamp = ON"
	endif
	
	sleep/S 0.1
	
	//Print Version:
	Print "\tVersion = " + serialportQuery("#04?9")[3,15]
End