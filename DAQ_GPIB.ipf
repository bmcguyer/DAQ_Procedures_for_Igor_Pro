#pragma rtGlobals=1		// Use modern global access method.
#pragma version = 3.0	// DAQ_GPIB version

//####[ DAQ_GPIB ]######################################################
//	Bart McGuyer, Department of Physics, Princeton University 2008
//	Provides GPIB initialization & communication routines, plus GPIB Control Panel.  
//	Acknowledgements:  
// -- This code comes from work performed while I was a graduate student 
//		in the research group of Professor William Happer, and builds on 
//		some previous code from that group.  
//	
//	DAQ_GPIB is intended to provide generic functions for initializing one gpib board 
//	and handling multiple devices. It is not intended to be device-specific (though all 
//	devices have their own preferrence for gpib terminators). Devices are specified 
//	for commands through "name" strings, which you setup with the initialization
//	routine. For example:  
//		Init_GPIB("5:scope;8:counter;")
//		gpibSend("counter", "*IDN?")
//	This inits gpib and sets "scope" and "counter" to refer to devices detected at 
//	addresses 5 and 8. The message "*IDN?\r" is then sent to "counter".
//	
//	Assumptions:
//	-- Igor Pro v5 and above
//	-- Wavemetrics NIGPIB2 XOP installed
//	-- Only one gpib board installed, with interface id "gpib0" and primary address 0.
//	-- Message termination: n/a.  Response termination:  "\n".  
//		These settings have worked for all equipment I've used.  
//	
//	Version Notes:
//	-- v3.0: 12/2/2011 - Slight modification before posting at www.igorexchange.com.
//	-- v2.0: 9/21/2009 - Cleaned up code a bit.
//	
//	Notes:
//	-- NI Device templates are NOT needed!  Init_GPIB automatically detects all devices.  
//	-- Changing Interface Properties in NI Measurement & Automation Explorer may affect GPIB communcation (!).
//	-- NI4882 calls set V_ibsta, V_iberr, V_ibcnt to the NI-4882 driver variables ibsta, iberr, ibcnt. 
//	-- Some GPIB2 commands return results in V_flag, S_value
//	-- Nothing's done to prevent errors from trying to setup the same name for multiple devices.
//	-- DON'T forget that you can use NIGPIB2 commands in your own code to supplement these!
//			Ex:  gpibSend(name, message); Sleep/T 2; GPIBRead2/T="/n" response
//		Igor times out on reading if the device takes too long, and the above method is the only way to accomodate slow devices.
//		If you want to do this, they you will probably find gpibSetDevice(name) to be useful.
//	-- Some devices (ex: Burleigh WA-1500) can't accept goto local or remote commands!
//	
//	####[ Table of Contents ]####
//	Windows:							Description:
//		gpibControlPanel				Panel for diagnosing GPIB, sending commands to devices, changing variables, etc.  Works without "names" setup.
//	Functions:						Description:
//		Init_GPIB						Sets up GPIB interface and global variables.  Accepts string of desired Igor device names ("id1:name1;") or "".
//		gpibSend							Send a command to a device, not expecting a response.  Carriage return automatically added to message.
//		gpibQuery						Send a command (with gpibSend), waits 0.001s, returns string response (term = "\r", "\n", or both).
//		gpibQueryBinary				Send a command (with gpibSend), waits 0.001s, returns string response to binary read.
//		gpibGotoLocal					Tells a device to switch to Local mode
//		gpibGotoLocalAll				Set all active devices to Local mode
//		gpibGotoRemoteAll				Set all active devices to remote mode
//		gpibReset						Best way to reset and clear GPIB interface.
//		gpibClear						Sends device clear message to a device.
//		gpibClearAll					Sends interface clear message to all devices.
//		gpibSetDevice					Sets device for send/read using "names", for people who want to do manual send/read with the naming ability
//	Static Functions: 			Description:	(Note: static functions are not accessible outside of this file)
//		gpibSetupDeviceNames()		Sets up Igor names for devices based upon contents of gDeviceNames
//		gpibDeleteUnusedNames()	Delete old name variable (gUD_*) that don't correspond to names in gDeviceNamesList


//####################################################################
// Static Variables		(allow easy dynamic changes of code, but ONLY work for functions - not Macros!)
Static strconstant ksGPIBpath = "root:System:GPIB"		//GPIB data folder location
Static strconstant ksGPIBpathParent = "root:System"		//Parent folder of data folder location, needed for Init_GPIB()



//####################################################################
//  GPIB Routines

//Init_GPIB:  Initializes GPIB interface and global variables.  
//NOTE:  Accepts string input for naming devices ("id1:name1;id2:name2"), or null string
Function Init_GPIB(devlist)
	String devlist								//Input for gDeviceNames, or null
	
	// Change to GPIB data folder
	String PreviousDataFolder = GetDataFolder(1)	//Save previous data folder
	NewDataFolder/O/S $ksGPIBpathParent		//Make sure parent folder exists
	NewDataFolder/O/S $ksGPIBpath				//Change to GPIB data folder
	
	//-----------------------------------------
	//	Setup Global Variables:
	
	String/G gDeviceNames				//List of device names for Igor.  Format "id1:name1;id2:name2;"
	If(!stringmatch(devlist,""))		//Fill gDeviceNames if devlist isn't empty.  
		gDeviceNames = devlist	
	endif
	Variable/G gBoardAddress = 0		//GPIB board address. Set to 0 for GPIB0 board. Usefull for NI4882 calls.
	Variable/G gBoardUD					//GPIB board UD ("unit descriptor")
	Variable/G gNumDevices=0			//Will store number of active GPIB devices
	//List of addresses to test for devices or other NI4882 commands. NOTE: -1 is NOADDR, marks end of list.
	Make/O gTestAddresses = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,-1}		
	//Note: Each row of the next four variables describes the same detected device.  
	Make/O/N=0/T gDeviceNamesList	//List of active device names
	Make/O/N=0 gDeviceAddressList	//List of active device addresses
	Make/O/N=0 gDeviceUDList			//List of active device UD's
	Make/O/N=0/T gDeviceIdentList	//List of active device Identification (response to "*IDN?", "ID?")
	
	//	Setup gpibControlPanel Variables
	Make/O/N=(0,4)/T CP_DeviceDisplay		//Spreadsheet of device data, displayed in control panel
		SetDimLabel 1,0,'Igor Name',CP_DeviceDisplay	//First column = Igor names
		SetDimLabel 1,1,'ID',CP_DeviceDisplay				//Second column = addresses
		SetDimLabel 1,2,'UD',CP_DeviceDisplay				//Third column = UD's
		SetDimLabel 1,3,'Description (*IDN? or ID?)',CP_DeviceDisplay	//Fourth column = identification (response to "*IDN?")
	Variable/G CP_UD = -1
	Variable/G CP_ID = -1
	Variable/G CP_Row = -1				//This value disables Manual Controls in gpibControlPanel, until a device is selected by mouse
	String/G CP_Send="*IDN?"			//Useful trial command to load into Manual Control section
	String/G CP_Read=""
	String/G CP_ReadBinary=""
	String/G CP_Name = ""
	
	//-----------------------------------------
	// SETUP THE GPIB BOARD:
	
	NI4882 ibfind={"gpib0"}; gBoardUD= V_flag	//Find and store the GPIB0 board UD
	NI4882 SendIFC={gBoardAddress}				//Make GPIB0 the CIC (controller in charge), otherwise get NI-488.2 Error ECIC
	GPIB2 board=gBoardUD							//Set active board for high-level GPIB operations

	//-----------------------------------------
	// SETUP DEVICES:

	// Find out how many devices exist, and store their addresses in gDeviceAddressList
	NI4882 FindLstn={gBoardAddress,gTestAddresses,gDeviceAddressList,30}	//Result stored in V_ibcnt
	gNumDevices = V_ibcnt
	
	// Error-check number of devices found
	If((gNumDevices) > 0 && (gNumDevices <= 30) && (gNumDevices == numpnts(gDeviceAddressList)))
		// Valid number of devices found
		
		//Resize Global Variables
		Redimension/N=(gNumDevices) gDeviceUDList, gDeviceIdentList, gDeviceNamesList
		Redimension/N=(gNumDevices,4) CP_DeviceDisplay
		
		// Loop over available devices to find and store UD's, test send and receive (store into gDeviceIdentList)
		Variable ii
		String dummy
		for(ii = 0; ii < gNumDevices; ii += 1)
			NI4882 ibdev={gBoardAddress,gDeviceAddressList[ii],0,10,1,0}//Query UD for device address from list
			gDeviceUDList[ii] = V_flag												//Save result UD
			
			//  Test send and receive by requesting device identification
			GPIB2 device=gDeviceUDList[ii]		//Set device for send/read
			GPIBWrite2 "*IDN?"// + "\r"			//Send identity query.  Could use \r\n termination?
			dummy = ""									//Reset dummy
			GPIBReadBinary2/Q/S=255 dummy		//Read response (Binary = safest way?).  No error on timeout.
			
			//  If answer null (linefeed on binary read), then try pre-NI488.2 ID Query (may freak out some devices)
			if(char2num(dummy)==10)
				GPIBWrite2 "ID?"// + "\r"			//Send outdated identity query.  Could use \r\n termination?
				GPIBReadBinary2/Q/S=255 dummy	//Read response (Binary = safest way?).  No error on timeout.
			endif
			
			//If answer still null or linefeed, then insert error string
			if((char2num(dummy) == 10) || (stringmatch(dummy, "")))
				dummy = "(no response)"
			endif
			
			gDeviceIdentList[ii] = dummy			//Store device identification 
		endfor
	elseif(gNumDevices == 0)
		//Print "No GPIB devices to setup!"
	else
		Print "#### ERROR during Init_GPIB():  gNumDevices = ", gNumDevices
		abort
	endif
	
	//-----------------------------------------
	
	gpibSetupDeviceNames()						//Setup variable names to hold UD's for accessing devices elsewhere in Igor
	gpibDeleteUnusedNames()					//Delete old variables that used to hold UD's, but aren't used anymore
	 
	//-----------------------------------------
	
	//Setup CP_DeviceDisplay for GPIB Control Panel
	CP_DeviceDisplay[][0] = gDeviceNamesList[p]
	CP_DeviceDisplay[][1] = num2str(gDeviceAddressList[p])
	CP_DeviceDisplay[][2] = num2str(gDeviceUDList[p])
	CP_DeviceDisplay[][3] = gDeviceIdentList[p]
	
	GPIB2 KillIO									// Init NIGPIB2, sends Interface Clear message (makes sure in nice state)
	
	SetDataFolder PreviousDataFolder		// Reset data folder to value before function call
	
	//  Print Status to History
	Printf "-- GPIB Initialized:  %d active devices.\r", gNumDevices	
End

//gpibSend:  Send a command to a device, not expecting a response.  Carriage return automatically added to message.
Function gpibSend(name,message)
	String name									//Name of device
	String message								//Message to send (without terminator)
	
	//Global Variable Reference:  
	NVAR gUD = $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + name))
	
	GPIB2 device = gUD						//Set device for send/read
	GPIBWrite2 message						//Send message -- don't add any terminators, except what command calls for!!!!
	
	//  Pause to let old/slow machines process... (rapid fire sends can cause problems)
	//Sleep/S 0.001								// Wait 0.001 second
	
	//if(V_flag == 0)							//Check if write was unsuccessful
	//	Print "Unsuccessful Write!"
	//	abort
	//endif
End

//gpibQuery:  Send a command (with gpibSend), waits 0.001s, returns string response (term = "\r", "\n", or both).
Function/S gpibQuery(name,message)
	String name									//Name of device
	String message								//Message to send (without terminator)
	
	gpibSend(name,message)					//Use gpibSend here to make sure termination is easy to change.
	
	//  Pause to let old/slow machines process... (rapid fire sends can cause problems)
	//Sleep/S 0.001								// Wait 0.001 second
	
	GPIBRead2/T="\n" message				//Read until \n (doesn't read linefeed \n, "ascii 10", which looks like a square)
	return message
End

//gpibQueryBinary:  Send a command (with gpibSend), waits 0.001s, returns string response to binary read.
Function/S gpibQueryBinary(name, message)
	String name									//Name of device
	String message								//Message to send (without terminator)
	
	gpibSend(name,message)					//Use gpibSend here to make sure termination is easy to change.
	
	//  Pause to let old/slow machines process... (rapid fire sends can cause problems)
	//Sleep/S 0.001								// Wait 0.001 second
	
	GPIBReadBinary2/S=255 message					
	return message
End

//gpibGotoLocalAll:  Set all active devices to Local mode
Function gpibGotoLocalAll()
	// Global Variables
	NVAR gNumDevices = $(ksGPIBpath + ":gNumDevices")
	WAVE gDeviceUDList = $(ksGPIBpath + ":gDeviceUDList")
	
	// Tell each device to go local
	variable ii
	for(ii = 0;  ii < gNumDevices; ii += 1)
		GPIB2 device = gDeviceUDList[ii]
		GPIB2 GotoLocal
	endfor
End

//gpibGotoLocal:  Tells a device to switch to Local mode
Function gpibGotoLocal(name)
	String name									//Name of device
	
	//Global Variable Reference:  
	NVAR gUD = $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + name))
	
	GPIB2 device = gUD						//Set device for send/read
	GPIB2 GotoLocal							//Tell device to go local
End

//gpibGotoRemoteAll:  Set all active devices to remote mode
Function gpibGotoRemoteAll()
	// Global Variables
	NVAR gBoardID = $(ksGPIBpath + ":gBoardID")
	WAVE gTestAddresses = $(ksGPIBpath + ":gTestAddresses")
	
	NI4882 EnableRemote={gBoardID, gTestAddresses}
End

//gpibReset:  Best way to reset and clear GPIB interface.
Function gpibReset()
	GPIB2 KillIO 
End

//gpibClearAll:  Sends interface clear message to all devices.
Function gpibClearAll()
	GPIB2 InterfaceClear
End

//gpibClear:  Sends device clear message to a device.
Function gpibClear(name)
	String name									//Name of device
	
	//Global Variable Reference:  
	NVAR gUD = $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + name))
	
	GPIB2 device = gUD						//Set device for send/read
	GPIB2 DeviceClear							//Tell device to clear
End

//gpibSetDevice:  Sets device for send/read using "names", for people who want to do manual send/read with the naming ability.
Function gpibSetDevice(name)
	String name									//Name of device
	
	//Global Variable Reference:  
	NVAR gUD = $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + name))
	
	GPIB2 device = gUD						//Set device for send/read
End



//####################################################################
//  Static Functions

//GPIB_SetupDeviceNames: Sets up Igor names for devices based upon contents of gDeviceNames
//Expected format is "id1;name1;id2;name2;".  Does nothing if gDeviceNames is empty.  
static Function gpibSetupDeviceNames()
	//Global Variables
	NVAR gNumDevices  = $(ksGPIBpath + ":gNumDevices")
	WAVE gDeviceAddressList  = $(ksGPIBpath + ":gDeviceAddressList")
	WAVE/T gDeviceNamesList  = $(ksGPIBpath + ":gDeviceNamesList")
	SVAR gDeviceNames  = $(ksGPIBpath + ":gDeviceNames")
	WAVE gDeviceUDList  = $(ksGPIBpath + ":gDeviceUDList")
	
	//Create variables that link the name to the device UD, update gDeviceNamesList
	variable ii, testID
	string temp
	for(ii = 0; ii < gNumDevices; ii +=1) 	//loop over found devices
		testID = gDeviceAddressList[ii]			//Store device address
		
		temp = StringByKey(num2str(testID), gDeviceNames)	//Get name associated with address
		
		if(!stringmatch(temp,""))					//Make sure name is not null string
			//Create global variable to hold ud, with user-desired name 
			Variable/G $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + temp)) = gDeviceUDList[ii]
			
			gDeviceNamesList[ii] = temp			//Update gDeviceNamesList
		endif
	endfor
End

//gpibDeleteUnusedNames:  Delete old name variable (gUD_*) that don't correspond to names in gDeviceNamesList
static Function gpibDeleteUnusedNames()
	// Change to GPIB data folder
	String PreviousDataFolder = GetDataFolder(1)	//Save previous data folder
	SetDataFolder $ksGPIBpath				//Change to GPIB data folder
	
	//Global Variables
	WAVE/T gDeviceNamesList = gDeviceNamesList
	WAVE/T CP_DeviceDisplay
	NVAR gNumDevices
	
	//Round up names of all variables used as Igor names for devices...
	String suspects
	suspects = VariableList("gUD_*",";",4)		//Returns a list of all global variables starting with "gUD_"
	
	String test_name, cmd
	Variable numItems = ItemsInList(suspects), ii, jj, tally
	
	//For each variable found, test if it's in gDeviceNamesList.  If not, delete it.  
	for(ii = 0; ii < numItems; ii += 1)			//Loop over suspects found	
		test_name = StringFromList(ii,suspects)	//Extract suspect name
		tally = 0									
		
		for(jj = 0; jj < gNumDevices; jj += 1)	//Loop over allowed device names
			tally += StringMatch(test_name, "gUD_" + gDeviceNamesList[jj])
		endfor
		
		if(tally == 0)		//If no matches found, delete the variable
			cmd = "KillVariables " + test_name
			Execute cmd
		endif					//NOTE:  Doesn't do anything if multiple copies found.
	endfor
	
	SetDataFolder PreviousDataFolder				// Reset data folder to value before function call
End



//####################################################################
//  GPIB Control Panel and buttons

//Add gpibControlPanel to the Macros menu
Menu "Macros"
	"GPIB Control Panel", gpibControlPanel()
End

//gpibControlPanel:  Panel for diagnosing GPIB, sending commands to devices, changing variables, etc.  Works without "names" setup.
Window gpibControlPanel() : Panel
	PauseUpdate; Silent 1		// building window...
	NewPanel /W=(800,50,1210,435) as "GPIB Control Panel"
	//ShowTools
	
	// Macro's DO NOT support static variables, so have to define the data folder path here: 
	string ksGPIBpath2 = "root:System:GPIB"
	
	//  Interface Controls Box
	GroupBox group2,pos={5,5},size={300,50},title="Interface Control"
	Button Button1,pos={15,25},size={50,20},proc=Button_GPIB_Init,title="Init",fstyle=1
	Button Button2,pos={75,25},size={50,20},proc=Button_GPIB_ClearAll,title="Clear"
	Button Button3,pos={135,25},size={50,20},proc=Button_GPIB_Reset,title="Reset"
	Button Button4,pos={195,25},size={100,20},proc=Button_GPIB_GotoLocalAll,title="Switch to Local"
	
	//  Active Devices Box
	GroupBox group0,pos={5,55},size={400,175},title="Active Devices"
	ListBox list0,pos={10,75},size={390,150}, proc=ListBox_GPIB_Devices
	ListBox list0,listWave=$(ksGPIBpath2 + ":CP_DeviceDisplay"),mode= 1,selRow= -1	//No row is initially selected
	ListBox list0,widths={75,20,45,500},userColumnResize= 0
	
	//  Manual Control
	GroupBox group1,pos={5,230},size={400,150},title="Manual Control"
	SetVariable setvar0,pos={15,252},size={70,16},title="GPIB ID:", noedit=1
	SetVariable setvar0,limits={30,-1,0},value= $(ksGPIBpath2 + ":CP_ID")
	Button button5,pos={100,250},size={75,20},proc=Button_GPIB_DeviceClear,title="Device Clear"
	Button button6,pos={185,250},size={100,20},proc=Button_GPIB_TestSendRead,title="Test Send/Read"
	Button button7,pos={295,250},size={100,20},proc=Button_GPIB_GotoLocal,title="Switch to Local"
	Button button8,pos={10,275},size={50,20},proc=Button_GPIB_Send,title="Send"
	SetVariable setvar1,pos={100,277},size={295,16},title=" "
	SetVariable setvar1,value= $(ksGPIBpath2 + ":CP_Send")
	Button button9,pos={10,300},size={50,20},proc=Button_GPIB_Query,title="Query"
	SetVariable setvar2,pos={100,302},size={295,16},title=" "
	SetVariable setvar2,value= $(ksGPIBpath2 + ":CP_Read")
	Button button10,pos={10,325},size={75,20},proc=Button_GPIB_QueryBinary,title="Query Binary"
	SetVariable setvar3,pos={100,327},size={295,16},title=" "
	SetVariable setvar3,value= $(ksGPIBpath2 + ":CP_ReadBinary")
	Button button11,pos={10,350},size={100,20},proc=Button_GPIB_ChangeName,title="Change Igor Name"
	SetVariable setvar4,pos={120,352},size={150,16},title="New Name: "
	SetVariable setvar4,value= $(ksGPIBpath2 + ":CP_Name")
	Button button12,pos={275,350},size={120,20},proc=Button_GPIB_DeleteUnusedNames,title="Delete Unused Names",fstyle=4

EndMacro

//Initialize GPIB, but don't change device names
Function Button_GPIB_Init(ctrlName) : ButtonControl
	String ctrlName
	Init_GPIB("")
End

//Sends interface clear
Function Button_GPIB_ClearAll(ctrlName) : ButtonControl
	String ctrlName
	gpibClearAll()
End

//Resets and clears GPIB
Function Button_GPIB_Reset(ctrlName) : ButtonControl
	String ctrlName
	gpibReset()
End

//Switches all devices to Local
Function Button_GPIB_GotoLocalAll(ctrlName) : ButtonControl
	String ctrlName
	gpibGotoLocalAll() 
End

//Routine to call when user click on list box.  Allows you to select a device for manual control.
Function ListBox_GPIB_Devices(ctrlName,row,col,event) : ListBoxControl
	String ctrlName
	Variable row
	Variable col
	Variable event	//1=mouse down, 2=up, 3=dbl click, 4=cell select with mouse or keys
						//5=cell select with shift key, 6=begin edit, 7=end
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	NVAR CP_Row = $(ksGPIBpath + ":CP_Row")
	SVAR CP_Name = $(ksGPIBpath + ":CP_Name")
	WAVE gDeviceAddressList = $(ksGPIBpath + ":gDeviceAddressList")
	WAVE gDeviceUDList = $(ksGPIBpath + ":gDeviceUDList")
	WAVE/T gDeviceNamesList = $(ksGPIBpath + ":gDeviceNamesList")
	
	switch(event)	
		case 4:		//If user selects a cell, prep variable so manual control affects that device.
			CP_ID = gDeviceAddressList[row]
			CP_UD = gDeviceUDList[row]
			CP_Name = gDeviceNamesList[row]
			CP_Row = row
			break					
	endswitch
	
	return 0
End

//Manual Control:  Sends device clear message to a device.  NOTE:  Doesn't depend on name!
Function Button_GPIB_DeviceClear(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	
	If(CP_ID != -1)	//Check if device selected in listbox
		GPIB2 device = CP_UD
		GPIB2 DeviceClear
	endif
End

//Manual Control:  Sends go to Local message to a device.  NOTE:  Doesn't depend on name!
Function Button_GPIB_GotoLocal(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	
	If(CP_ID != -1)	//Check if device selected in listbox
		GPIB2 device = CP_UD
		GPIB2 GotoLocal
	endif
End

//Manual Control:  Sends message to a device., no termination added!  NOTE: Doesn't depend on name!
Function Button_GPIB_Send(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	SVAR CP_Send = $(ksGPIBpath + ":CP_Send")
	
	If(CP_ID != -1)		//Check if device selected in listbox
		GPIB2 device = CP_UD
		GPIBWrite2 CP_Send// + "\r\n"
	endif
End

//Manual Control:  Queries device with message, no termination added!  NOTE: Doesn't depend on name!
Function Button_GPIB_Query(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	SVAR CP_Send = $(ksGPIBpath + ":CP_Send")
	SVAR CP_Read = $(ksGPIBpath + ":CP_Read")
	SVAR CP_Name = $(ksGPIBpath + ":CP_Name")
	
	If(CP_ID != -1)		//Check if device selected in listbox
		GPIB2 device = CP_UD
		GPIBWrite2 CP_Send// + "\r\n"
		//Sleep/S 2						//Sleep in seconds
		//CP_Read = ""
		GPIBRead2/T="\n" CP_Read	//Terminators = \n, linefeed.
	endif
End

//Manual Control:  Queries device with message, no termination added, but reads binary!  NOTE: Doesn't depend on name!
Function Button_GPIB_QueryBinary(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	SVAR CP_Send = $(ksGPIBpath + ":CP_Send")
	SVAR CP_ReadBinary = $(ksGPIBpath + ":CP_ReadBinary")
	
	If(CP_ID != -1)		//Check if device selected in listbox
		GPIB2 device = CP_UD
		GPIBWrite2 CP_Send// + "\r\n"
		//Sleep/S 0.001					//Sleep in seconds
		//CP_ReadBinary = ""
		GPIBReadBinary2/S=255 CP_ReadBinary
		//GPIBReadBinary2/S=2000 CP_ReadBinary
	endif
End

//Manual Control:  Tests send and receive with device, using ...Query and ...QueryBinary.  NOTE: Doesn't depend on name!
Function Button_GPIB_TestSendRead(ctrlName) : ButtonControl
	String ctrlName
	
	SVAR CP_Send = $(ksGPIBpath + ":gCP_Send")
	CP_Send = "*IDN?"
	
	Button_GPIB_Query(ctrlName)
	Button_GPIB_QueryBinary(ctrlName)
End

//Manual Control:  Changes name of a device, without deleting old name.  NOTE: Doesn't depend on name!
Function Button_GPIB_ChangeName(ctrlName) : ButtonControl
	String ctrlName
	
	//Global Variables
	NVAR CP_ID = $(ksGPIBpath + ":CP_ID")
	NVAR CP_UD = $(ksGPIBpath + ":CP_UD")
	NVAR CP_Row = $(ksGPIBpath + ":CP_Row")
	SVAR CP_Name = $(ksGPIBpath + ":CP_Name")
	WAVE/T gDeviceNamesList = $(ksGPIBpath + ":gDeviceNamesList")
	WAVE/T CP_DeviceDisplay = $(ksGPIBpath + ":CP_DeviceDisplay")
	
	If((CP_ID != -1)&&(CP_Row != -1)&&(!stringmatch((CP_Name),"")))		//Check if new name Null, or if device isn't selected yet.
		//Create global variable to hold ud, with user-desired name 
		Variable/G $(ksGPIBpath + ":" + PossiblyQuoteName("gUD_" + CP_Name)) = CP_UD
		
		//Also update the names lists
		gDeviceNamesList[CP_Row] = CP_Name
		CP_DeviceDisplay[CP_Row][0] = gDeviceNamesList[CP_Row]
	elseif((CP_ID != -1)&&(CP_Row != -1))
		Print "#### ERROR during Button_GPIB_ChangeName():  Empty name!"
	endif
End

//Deletes unused device names.
Function Button_GPIB_DeleteUnusedNames(ctrlName) : ButtonControl
	String ctrlName
	 gpibDeleteUnusedNames()
End

