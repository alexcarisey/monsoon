macro "Leica GSDIM Data Extractor" {

// Leica GSDIM data extractor (DAX or TIF)
// based on Leica LIF Extractor macro by Christophe Leterrier
//
// version 1.9 14/05/2014
// tested with ImageJ 1.48v within Fiji implementation, LOCI Bio-Formats 14/05/2014
//
// 1.0 > initial version
// 1.1 > add the number of frames and save the log file
// 1.2 > built-in stack cutter
// 1.3 > image warping and new GUI
// 1.4 > if the stacks are cropped, the log file is now correct
// 1.5 > create .inf files for Insight3 and amazingly handsome log files
// 1.6 > read several microscope hardware settings directly from the lif file (EMCCD gain, preamp gain, binning, temp, sizeX and Y, microscope model and camera name)
// 1.7 > Fixed a potential bug in the frame counting for the lif in case the user sets a higher limit for cropping than total frame count
// 1.8 > Modified the 'Custom folder for each stack' option to allow the user to set a remote folder at the beginning of the analysis (instead of before each stack)
// 1.9 > Fix annoying bug that would count all the files in the total instead of just the number of lif files

// Precautionary measures...

requires("1.48m");

// User input to select the folder that contains the stacks to analyse

datapaths = getDirectory("Choose directory where your stacks are stored");

// Create an array with the name of the stacks to analyse

stacklist = getFileList(datapaths);
number_of_stacks = lengthOf(stacklist);
stackextensionlist=newArray(stacklist.length);

// Create an array for the extensions of the files

for (i=0; i<stacklist.length; i++) {
	length_stack=lengthOf(stacklist[i]);
	stackextensionlist[i]=substring(stacklist[i],length_stack-4,length_stack);
}

// Count the number of lif files

number_of_lif = 0;

for (n=0; n<stackextensionlist.length; n++) {
	if (stackextensionlist[n] == ".lif") {
	number_of_lif++;
	}
}

if (number_of_lif == 0) {
	exit("This folder doesn't contain any lif file!");
}

// Initialize variables

format_array = newArray(".dax", ".tif");
save_array = newArray("In the source folder", "In a subfolder of the source folder", "In a folder next to the source folder", "Somewhere else");
analysed_stuff = false;
decision = 1;

// Creation of the dialogue box

Dialog.create("Leica GSDIM Data Extractor");
Dialog.addMessage("Leica GSDIM data extractor v1.9 - May 2014");
Dialog.addMessage("Source folder: " + datapaths);
Dialog.addMessage("Number of files detected: " + number_of_lif);
Dialog.addMessage("\n");
Dialog.addChoice("Output format", format_array, ".dax");
Dialog.addChoice("Export location", save_array, "In the source folder");
Dialog.addCheckbox("Image warping", false);
Dialog.addMessage("\n");
Dialog.addCheckbox("Create .inf files for Insight3", false);
Dialog.addCheckbox("Force the EMCCD gain to 30", false);
Dialog.addMessage("\n");
Dialog.addCheckbox("Crop on import", false);
Dialog.addNumber("Beginning:", 1001);
Dialog.addNumber("End:", 11000);
Dialog.addMessage("Note that if you select a frame range, the virtual stack mode is disabled.");

Dialog.show();

format_choice=Dialog.getChoice();
saving_choice=Dialog.getChoice();
image_warping_choice = Dialog.getCheckbox();
inf_file_choice=Dialog.getCheckbox();
force_gain=Dialog.getCheckbox();
crop_choice = Dialog.getCheckbox();
beginning_choice = Dialog.getNumber();
end_choice = Dialog.getNumber();
frames_quantity = end_choice - beginning_choice + 1;

setBatchMode(true);

// Create and populate information for the log file

f1 = "["+"Log_Leica_GSDIM_data_extractor"+"]";
run("Text Window...", "name=" + f1 + " width=90 height=50");

print(f1,"----------------------------------------------------------------------------------\n");
print(f1,"Leica GSDIM data extractor v1.9 - May 2014\n");
print(f1,"----------------------------------------------------------------------------------\n");
print(f1,"\n");
print(f1,"General settings:\n\n");
print(f1,"Source folder : " + datapaths + "\n");

if (crop_choice == true){
	print(f1,"All the exported stacks will include frames " + beginning_choice + " to " + end_choice + " unless the original file contains less frames than the defined boundaries.\n");
}
else {
	print(f1,"The exported stacks will not be cropped.\n");
}

// Find the warp file

if (image_warping_choice == true) {
	transformation_file_path=File.openDialog("Select a warp file");
	print(f1,"Image warping will be applied to all stacks using the transformation file " + transformation_file_path + ".\n");
	}
	else {
	print(f1,"No image warping will be applied.\n");
}

// Loop on all lif extensions (and only lif extension files!)

for (n=0; n<stackextensionlist.length; n++) {

if (stackextensionlist[n] == ".lif") {
	
	// Get the file path
	
	file_path=datapaths+stacklist[n];
	
	// Update a variable to define a proper exit for of the macro in case no lif files are found
	
	analysed_stuff = true;
	
	// Store components of the file name
	
	file_name=File.getName(file_path);
	file_path_length=lengthOf(file_path);
	file_name_length=lengthOf(file_name);
	file_dir=substring(file_path,0,file_path_length-file_name_length);
	file_shortname=substring(file_name,0,file_name_length-4);
	
	// Localise or create the output folder
	
	if(saving_choice == "In the source folder") {
		output_dir=file_dir;
	}
	if(saving_choice == "In a subfolder of the source folder") {
		if(format_choice == ".dax") {
			output_dir=file_dir+file_shortname+"_DAX"+File.separator;
		}
		if(format_choice == ".tif") {
			output_dir=file_dir+file_shortname+"_TIF"+File.separator;
		}
		File.makeDirectory(output_dir);
	}
	if(saving_choice == "In a folder next to the source folder") {
		output_dir=File.getParent(file_path);
		if(format_choice == ".dax") {
		output_dir=output_dir+"_"+file_shortname+"_DAX"+File.separator;
		}
		if(format_choice == ".tif") {
		output_dir=output_dir+"_"+file_shortname+"_TIF"+File.separator;
		}
		File.makeDirectory(output_dir);
	}
	if(saving_choice == "Somewhere else") {
		if (decision ==1) {
			output_dir=getDirectory("Choose the save folder");
			decision++;
		}
	}

	// Start BioFormats and get series number in lif file

	run("Bio-Formats Macro Extensions");
	Ext.setId(file_path);
	Ext.getSeriesCount(series_count);
	series_names=newArray(series_count);
	
	// Output for the user via the log window
	
	print(f1,"\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"File " + n+1 + " out of " + number_of_stacks + " :" + file_name + " with " + series_count + " series.\n");
	print(f1,"Destination directory: " + output_dir + "\n");

	// Loop on the whole lif file to extract the relevant Series
	
	for (i=0; i<series_count; i++) {
		
		// Get series name and channels count

		Ext.setSeries(i);						// Set the current series
		Ext.getEffectiveSizeC(channel_count);	// Count the number of channels per series (should always be one, in our case)
		series_names[i]="";						// Create an empty variable to store the names
		Ext.getSeriesName(series_names[i]);     // Get the name of the series
		Ext.getSizeT(series_frames);            // Count the number of frames per series
		
		// Analyse the naming of the Series to find THE ONE

		criterionA = indexOf(series_names[i],"GSD");
		criterionB = indexOf(series_names[i],"_el_");
		
		// Main loop to extract the relevant series
		
		if(criterionA == 0 && criterionB == -1) {
		
		if(crop_choice == true) {
			if(beginning_choice > series_frames) {
				beginning_choice = series_frames;
				frames_quantity = end_choice - beginning_choice + 1;
			}
			if(end_choice > series_frames) {
				end_choice = series_frames;
				frames_quantity = end_choice - beginning_choice + 1;
			}
			print(f1,"Series " + i + ": " + series_names[i] + " with " + series_frames + " frames in total but exported file contains only " + frames_quantity + " frames [" + beginning_choice + "-" + end_choice + "].\n");
		}
		else {
			print(f1,"Series " + i + ": " + series_names[i] + " with " + series_frames + " frames.\n");
			frames_quantity = series_frames;
		}

		// Import the series (split channels and crop on import if selected in dialogue box)
		
		run("Bio-Formats Importer", "open=["+ file_path + "] view=[Standard ImageJ] stack_order=Default use_virtual_stack series_"+d2s(i+1,0));

		// Extract the metadata from the stack (camera settings, etc...)

		EM_gain_value="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|EMGainValue",EM_gain_value);
		Ext.getSizeX(image_size_X);
		Ext.getSizeY(image_size_Y);
		microscope_model="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|MicroscopeModel",microscope_model);
		camera_name="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|WideFieldChannelConfigurator|CameraName",camera_name);
		Camera_other_gain_value="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|GainValue",Camera_other_gain_value);
		camera_temperature="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|TargetTemperature",camera_temperature);
		camera_binning="";
		Ext.getSeriesMetadataValue("ATLCameraSettingDefinition|CameraFormat|Binning",camera_binning);
			
		// Loop on each channel (each opened window)
		
		for(j=0; j<channel_count; j++) {
			
			// Construct window name
			
			temp_channel=d2s(j,0);

			// Windows title has series name in it only if more than one series is present in the lif file
			
			if(series_count==1) {
				source_window_name=file_shortname+ " - C="+temp_channel;
			}
			else {
			source_window_name=file_shortname+" - "+series_names[i]+" - C="+temp_channel;
			}
			TYPE="";
		
			// Rename image according to processing
			
			new_window_name=file_shortname+" - "+series_names[i];
			rename(new_window_name);

			print(f1,"New file name: " + new_window_name + "\n");
		
			// Crop the substack if required
		
			if(crop_choice == true) {
				if(beginning_choice>=series_frames) {
					beginning_choice = series_frames;
				}
				if(end_choice>=series_frames) {
					end_choice = series_frames;
				}
				run("Duplicate...", "title=["+new_window_name+"] duplicate range=" + beginning_choice + "-" + end_choice);
			}
		
			// Apply the image warping if required and add an extension to the output file
			
			if(image_warping_choice == true) {
				run("MultiStackReg", "action_1=[Load Transformation File] file_1=" + transformation_file_path + " stack_2=None action_2=Ignore file_2=[] transformation=Affine");
				new_window_name = new_window_name + "_trans";
				}

			// Create output file path and save the output image
			
			//output_path="Void";
			
			if(format_choice == ".dax") {
				output_path=output_dir+new_window_name+".dax";
				saveAs("Raw Data",output_path);
			}
			if(format_choice == ".tif") {
				output_path=output_dir+new_window_name+".tif";
				save(output_path);
			}
		
			// Create the .inf file if required
			
			if(force_gain == true) {
			EM_gain_value = 30;
			}
			
			if(inf_file_choice == true) {
				f2 = "[" + new_window_name + "]";
				run("Text Window...", "name="+f2+" width=72 height=21");
				print(f2,"[INF_header]\n");
				print(f2,"INF_version = 2\n");
				print(f2,"DAX_file_path = \"" + output_path + "\"\n");
				print(f2,"DAX_data_type = \"I16_big_endian\"\n");
				print(f2,"machine_name = \"" + microscope_model + "\"\n");
				print(f2,"\n");
				print(f2,"[Camera_configuration]\n");
				print(f2,"frame_X_min = 129\n");
				print(f2,"frame_Y_min = 129\n");
				print(f2,"frame_X_size = " + image_size_X + "\n");
				print(f2,"frame_Y_size = " + image_size_Y + "\n");
				print(f2,"camera_model = \"" + camera_name + "\"\n");
				print(f2,"HS_speed = \"10_MHz\"\n");
				print(f2,"preamp_gain = \"" + Camera_other_gain_value + "\"\n");
				print(f2,"VS_speed = \"0.59_MHz\"\n");
				print(f2,"VCV_amplitude = \"Normal\"\n");
				print(f2,"crop_mode = \"OFF\"\n");
				print(f2,"CCD_mode = \"frame-transfer\"\n");
				print(f2,"recording_mode = \"continuous\"\n");
				print(f2,"requested_number_of_frames = 20\n");
				print(f2,"requested_frame_rate = 0.000000\n");
				print(f2,"requested_exposure_time = 0.100000\n");
				print(f2,"binning = " + camera_binning + "\n");
				print(f2,"frame_rate = 9.911785\n");
				print(f2,"exposure_time = 0.100000\n");
				print(f2,"EM_gain_mode = \"linear\"\n");
				print(f2,"EMCCD_gain = " + EM_gain_value + "\n");
				print(f2,"camera_temperature = " + camera_temperature + "\n");
				print(f2,"laser_control = \"manual\"\n");
				print(f2,"number_of_frames = " + frames_quantity + "[INF_v1_compatibility]\n");
				print(f2,"machine name = " + microscope_model + "\n");
				print(f2,"frame dimensions = " + image_size_X + " x " + image_size_Y + "\n");
				print(f2,"binning = " + camera_binning + " x " + camera_binning + "\n");
				print(f2,"number of frames = " + frames_quantity + "\n");
				print(f2,"preamp gain = " + Camera_other_gain_value + "\n");
				print(f2,"EMCCD gain = " + EM_gain_value + "\n");
				run("Text...", "save=" + "[" + output_dir + new_window_name + ".inf]");
				selectWindow(new_window_name + ".inf");
				run("Close");
			}

		}

		}

	}

}

}

// Final message within the status bar

showStatus("Leica GSDIM Data Extractor has finished to export your files.");

print(f1,"\n");
print(f1,"----------------------------------------------------------------------------------\n");
print(f1,"\n");
print(f1,"Leica GSDIM Data Extractor has finished to export your files.\n");

// Save the content of the log window for future reference only if at least one file has been extracted (see analysed_stuff switch)

if(analysed_stuff == true) {
	selectWindow("Log_Leica_GSDIM_data_extractor");
	saveAs("Text", file_dir+"Log_Leica_GSDIM_data_extractor");
	}
	else {
	print(f1,"No lif files were present in the designated folder. :(\n");
	}

}
