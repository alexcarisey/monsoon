macro "ThunderSTORM batch processor" {

// Batch processing with GUI for ThunderSTORM developed by Martin Ovesný, Pavel Křížek, Josef Borkovec, Zdeněk Švindrych, and Guy M. Hagen
// at the Charles University in Prague. Source code available here: http://thunder-storm.googlecode.com
//
// version 2.3 26/07/2014
// tested ThunderSTORM dev-2014-07-15-b1, ImageJ 2.0.0-rc-6/1.49b
// some parts are based on Leica LIF Extractor macro by Christophe Leterrier
//
// 1.0 > Initial version.
// 1.1 > Building-up the filtering steps online through GUI.
// 1.2 > New log file, fixed a bug in creating the filter string, selection of output visualisation works now, more detection filters enabled, 3D options out.
// 1.3 > Default filtering string, possibility to choose the scaling of visualisation output.
// 1.4 > Code cleanup.
// 1.5 > Multimode analysis/filtering.
// 1.6 > Longer waiting pause after single step detection+filtering because of the unpredictable length of the 'merging' step and the subsequent high risk for crash (issue with Charlotte's data with >10^6 raw events).
// 1.7 > Fix a bug in final image saving for lif files and added the possibility to save the drift correction graphs.
// 1.8 > Added the possibility to change the magnification for the drift correction by cross-correlation [reduce to 2 or 3 if drift correlation fails].
// 1.9 > Bug fix (in the CSV re-analysing part).
// 2.0 > Modification of the pre-set parameters for detection. 
// 2.1 > The parameters used for detection are now listed in the log file, 'remove duplicate' feature removed because we don't use the MFA algorithm. Changed the default filtering string following suggestions to remove the upper boundary of sigma.
// 2.2 > Better set of rules for recognition of GSD stacks within .lif files (avoid loading dodgy stacks or 'pumping' stacks) and improvement of the info displayed in the log file. Export the chi2 value if LSQ fitting selected.
// 2.3 > Additional functions for 2-colour imaging (chromatic aberration correction and reversing stacks for X-correlation).


// Precautionary measures...

	requires("1.48t");

// Initialise variables

	current_version_script = "v2.3";
	connectivity_array = newArray("4-neighbourhood", "8-neighbourhood");
	method_array = newArray("Least squares","Weighted Least squares","Maximum likelihood");
	save_array = newArray("In the source folder", "In a subfolder of the source folder", "In a folder next to the source folder", "Somewhere else");
	visualisation_array = newArray("Averaged shifted histograms (2D)", "Normalized Gaussian (2D)", "No visualization");
	first_stack = 1;
	progression_index = 0;
	gui_twocolours = false;
	channel_warping = false;
	inverted_drift_correction = false;

// Initial GUI to select between analysis and/or filtering modes

	gui_choice_list = newArray("Detection & post-processing (TIF stacks)", "Detection & post-processing (LIF files)", "Post-processing (CSV files)", "Visualisation (CSV files)");

	Dialog.create("ThunderSTORM Batch Processor");
	Dialog.addMessage("ThunderSTORM Batch Processor " + current_version_script);
	Dialog.addMessage("");
	Dialog.addChoice("          Select the mode  ", gui_choice_list, "Detection & post-processing (TIF stacks)");
	Dialog.addCheckbox("Enable 2-colour specific functions", false);
	Dialog.addMessage("");
	Dialog.addMessage("Help notes:");
	Dialog.addMessage("");
	Dialog.addMessage("Detection & post-processing (TIF stacks)");
	Dialog.addMessage("- This mode allows the detection of molecules from tif stacks with or without subsequent filtering.");
	Dialog.addMessage("  Detection will be carried out using the recommanded method but you can change the settings (see lab's wiki).");
	Dialog.addMessage("");
	Dialog.addMessage("Detection & post-processing (LIF files)");
	Dialog.addMessage("- Same as above but directly from the Leica lif files. You must have only one GSD series per lif file.");
	Dialog.addMessage("  This is a limitation of the Bio-Formats importer plugin for ImageJ/Fiji.");
	Dialog.addMessage("");
	Dialog.addMessage("Post-processing (CSV files)");
	Dialog.addMessage("- Allows to filter the events of a CSV file (use your *all_events.csv files) using different parameters.");
	Dialog.addMessage("");
	Dialog.addMessage("Visualisation (CSV files)");
	Dialog.addMessage("- To plot new HR images from a data table supplied as a CSV file.");
	Dialog.addMessage("");
	Dialog.addMessage("Enable 2-colour specific functions");
	Dialog.addMessage("- For 2-colour imaging: allows to perform chromatic aberration correction using a transformation matrix");
	Dialog.addMessage("  and inversion of the first stack acquired before performing drift correction to minimise artefactual shift.");

	Dialog.show();

	gui_choice = Dialog.getChoice();
	gui_twocolours = Dialog.getCheckbox();

// ----------------- MODE 1: DETECT AND FILTER FROM THE TIF STACKS ----------------------------------------------------------------------------------------------------------------------------------------

	if(gui_choice == "Detection & post-processing (TIF stacks)") {

// Load the source folder

		datapaths = getDirectory("Choose directory where your stacks are stored");

// Create an array with the name of the stacks to analyse

		stacklist_all = getFileList(datapaths);
		number_of_files = lengthOf(stacklist_all);
		stackextensionlist=newArray(stacklist_all.length);

// Create an array for the extensions of the files

		for (i=0; i<stacklist_all.length; i++) {
			length_stack=lengthOf(stacklist_all[i]);
			stackextensionlist[i]=substring(stacklist_all[i],length_stack-4,length_stack);
		}

		number_of_tif = 0;
		for (n=0; n<stackextensionlist.length; n++) {
			if (stackextensionlist[n] == ".tif") {
				number_of_tif++;
			}
		}
		if(number_of_tif == 0) {exit("This folder doesn't contain any tif file!");} // Exit if no file detected

// Creation of the dialogue box

		Dialog.create("ThunderSTORM Batch Processor");
		Dialog.addMessage("ThunderSTORM Batch Processor " + current_version_script + "");
		Dialog.addMessage("Source folder: " + datapaths + " with " + number_of_tif + " tif stacks.");
		if(gui_twocolours == true) {
		Dialog.addCheckbox("Image warping [you will provide the transformation matrice in the next step]", true);
		Dialog.addString("           Keyword for channel to warp:", "green", 25);
		Dialog.addCheckbox("Inverted drift correction for 1st channel acquired", false);
		Dialog.addString("           Keyword for channel to reverse:", "green", 25);
		}
		Dialog.addMessage("Detection parameters to use:");
		Dialog.addMessage("Filter: Wavelet filter (B-Spline)");
		Dialog.addNumber("           B-Spline order", 3, 0, 25,"");
		Dialog.addNumber("           B-Spline scale", 2.0, 0, 25,"");
		Dialog.addMessage("Detector: Local maximum");
		Dialog.addString("           Peak intensity threshold", "2*std(Wave.F1)", 25);
		Dialog.addChoice("Connectivity", connectivity_array, "8-neighbourhood");
		Dialog.addMessage("Estimator: PSF: Integrated Gaussian");
		Dialog.addNumber("           Fitting radius [px]", 5, 0, 25,"");
		Dialog.addChoice("Method", method_array, "Weighted Least squares");
		Dialog.addString("           Initial sigma [px]", 1.6, 25);
		Dialog.addMessage("");
		Dialog.addMessage("Post-processing:");
		Dialog.addCheckbox("No filtering at all (only detection)", true);
		Dialog.addCheckbox("Filtering", false);
		Dialog.addString("Filtering string:", "intensity>500 & sigma>10 & uncertainty<50", 25);
		Dialog.addCheckbox("Drift correction by cross-correlation", false);
		Dialog.addNumber("           Number of bins:", 5, 0, 25,"");
		Dialog.addNumber("            Magnification:", 3, 0, 25,"");
		Dialog.addCheckbox("Save the drift correction plot", true);
		Dialog.addCheckbox("Merging", false);
		Dialog.addNumber("           Distance threshold [nm]:", 10, 0, 25,"");
		Dialog.addNumber("           Number of dark frames:", 0, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addMessage("Visualization:");
		Dialog.addChoice("Select rendering method", visualisation_array, "Averaged shifted histograms (2D)");
		Dialog.addNumber("           Magnification:", 10, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addChoice("Save output", save_array, "In the source folder");
		Dialog.addString("           Extension for filtered outputs:", "filtered", 25);

		Dialog.show();

		if(gui_twocolours == true) {
		channel_warping = Dialog.getCheckbox();
		channel_warping_keyword = Dialog.getString();
		inverted_drift_correction = Dialog.getCheckbox();
		inverted_drift_correction_keyword = Dialog.getString();
		}
		wavelet_order = Dialog.getNumber();
		wavelet_scale = Dialog.getNumber();
		peak_threshold = Dialog.getString();
		connectivity = Dialog.getChoice();
		fitting_radius = Dialog.getNumber();
		fitting_method = Dialog.getChoice();
		fitting_initial_sigma = Dialog.getString();

		cancel_filtering = Dialog.getCheckbox();
		do_filtering = Dialog.getCheckbox();
		filtering_string = Dialog.getString();
		do_driftcorrection = Dialog.getCheckbox();
		drift_correction_bins = Dialog.getNumber();
		drift_correction_magnification = Dialog.getNumber();
		save_driftcorrection_plot = Dialog.getCheckbox();
		do_merging = Dialog.getCheckbox();
		merging_distance = Dialog.getNumber();
		merging_offframes = Dialog.getNumber();
		visualization_choice = Dialog.getChoice();
		magnification_scale = Dialog.getNumber();
		saving_location_choice = Dialog.getChoice();
		extension_filtered_output = Dialog.getString();

// Find the warp file

	if (channel_warping == true) { transformation_file_path=File.openDialog("Select a warp file"); }

// Create and populate information for the log file

		f1 = "[Log_file]";
		run("Text Window...", "name="+f1+" width=90 height=40");

		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"ThunderSTORM batch processor " + current_version_script + "\n");
		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"\n");
		print(f1,"Source folder: " + datapaths + " contains " + number_of_tif + " stacks.\n");
		if (channel_warping == true) { print(f1,"Image warping will be applied to the stacks with the keyword \"" + channel_warping_keyword + "\" using the transformation file " + transformation_file_path + ".\n"); }
		print(f1,"Image filtering: Wavelet filter with order = " + wavelet_order + " and scale = " + wavelet_scale + ".\n");
		print(f1,"Approximate localisation of molecules: Local maximum method with a peak intensity threshold of " + peak_threshold + " and a connectivity of " + connectivity + ".\n");
		print(f1,"Sub-pixel localisation of molecules: PSF Integrated Gaussian method using " + fitting_method + " fitting with a fitting radius of " + fitting_radius + " px and an initial sigma of " + fitting_initial_sigma + " px.\n");
		if (cancel_filtering == true) { print(f1,"No post-processing selected.\n"); }
		if (do_filtering == true) { print(f1,"Filtering string applied to the data table: " + filtering_string +".\n"); }
		if (do_driftcorrection == true) { print(f1,"Drift-correction applied with " + drift_correction_bins + " bins and a magnification scale of " + drift_correction_magnification + ".\n"); }
		if (do_merging == true) { print(f1,"Events detected within " + merging_distance + "nm and with " + merging_offframes + " off-frame maximum will be merged.\n"); }

// Shows up the camera settings window to allow the user to verify the settings

		print(f1,"\nPlease review your camera settings.\n");
		run("Camera setup");

// Final warning

		print(f1,"Beginning of the batch processing.\n");

// Beginning of the main loop for one tif file

		for (n=0; n<stackextensionlist.length; n++) {

			if (stackextensionlist[n] == ".tif") {

// Select the next tif file to analyse and set the destination folder

				file_path=datapaths+stacklist_all[n];

				file_name=File.getName(file_path);
				file_path_length=lengthOf(file_path);
				file_name_length=lengthOf(file_name);
				file_dir=substring(file_path,0,file_path_length-file_name_length);
				file_shortname=substring(file_name,0,file_name_length-4);

				if(saving_location_choice == "In the source folder") {
					output_dir=file_dir;
				}

				if(saving_location_choice == "In a subfolder of the source folder") {
					output_dir=file_dir+file_shortname+File.separator;
					File.makeDirectory(output_dir);
				}

				if(saving_location_choice == "In a folder next to the source folder") {
					output_dir=File.getParent(file_path);
					output_dir=output_dir+"_"+file_shortname+File.separator;
					File.makeDirectory(output_dir);
				}

				if(saving_location_choice == "Somewhere else") {
					if (first_stack ==1) {
						output_dir=getDirectory("Choose the folder to save the files");
						first_stack++; // This allows this loop to run only once to select the destination folder
					}
				} // end of destination folder setup

// Detection loop

	open(file_path);

	progression_index++;

	print(f1,"\nFile " + progression_index + " out of " + number_of_tif + ": " + stacklist_all[n] + " loaded.\n");

	selectWindow(stacklist_all[n]);

	// Apply the image warping if required, check that the keyword is found and add an extension to the output file
		
	if(channel_warping == true) {

		criterionC = indexOf(stacklist_all[n],channel_warping_keyword);	// Analyse the naming of the tif file to find if it contains the keyword for warping

		if(criterionC != -1) {
			print(f1,"File: " + stacklist_all[n] + " --> image warping in progress...\n");
			run("MultiStackReg", "stack_1=[" + stacklist_all[n] + "] action_1=[Load Transformation File] file_1=" + transformation_file_path + " stack_2=None action_2=Ignore file_2=[] transformation=Affine");
			print(f1,"File: " + stacklist_all[n] + " --> image warping completed.\n");
		} else {
			print(f1,"The keyword for image warping hasn't been found in this stack.\n");
		}

	}

	print(f1,"File: " + stacklist_all[n] + " --> detection in progress...\n");

	// ThunderSTORM detection run

	selectWindow(stacklist_all[n]);

	run("Run analysis", "filter=[Wavelet filter (B-Spline)] scale="+ wavelet_scale + " order=" + wavelet_order + " " +
	"detector=[Local maximum] connectivity=" + connectivity + " threshold=" + peak_threshold + " " +
	"estimator=[PSF: Integrated Gaussian] sigma=" + fitting_initial_sigma + " method=[" + fitting_method + "] " +
	"full_image_fitting=false fitradius=" + fitting_radius + " mfaenabled=false renderer=[No Renderer]");

	current_root_stack_name = replace(stacklist_all[n], '.tif', '');

	run("Show results table");

	run("Export results", "filepath=[" + output_dir + current_root_stack_name + "_allevents.csv] fileformat=[CSV (comma separated)] " + 
		"id=true frame=true sigma=true chi2=true bkgstd=true intensity=true saveprotocol=true offset=true uncertainty=true y=true x=true");

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + current_root_stack_name + "_allevents.tif");
		close(current_root_stack_name + "_allevents.tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + current_root_stack_name + "_allevents.tif");
		close(current_root_stack_name + "_allevents.tif");
	}

	print(f1,"File: " + stacklist_all[n] + " --> detection completed.\n");

	// Filtering loop (nested within detection loop)

	if (cancel_filtering == false) { // Skip the loop if user didn't request any filtering step

		print(f1,"File: " + stacklist_all[n] + " --> data filtering in progress...\n");

	if (do_filtering == true) {
		filtering_command = "run(\"Show results table\", \"action=filter formula=[" + filtering_string + "]\")";
		eval(filtering_command);
		wait(15000);
	}		// End of filtering step

	if (do_driftcorrection == true) {
		run("Show results table", "action=drift magnification=" + drift_correction_magnification + " save=false showcorrelations=false method=[Cross correlation] steps=" + drift_correction_bins);
		wait(5000);
		selectWindow("Drift");
		if (save_driftcorrection_plot == true) {
			saveAs("Tiff", output_dir + current_root_stack_name + "_" + extension_filtered_output + "_driftplot.tif");
			close(current_root_stack_name + "_" + extension_filtered_output + "_driftplot.tif");
			};
		else {
			close("Drift");
			};
		wait(15000);
	}		// End of drift correction step

	if (do_merging == true) {
		run("Show results table", "action=merge offframes=" + merging_offframes + " zcoordweight=0.1 dist=" + merging_distance);
		wait(90000);
	}		// End of merging step

	run("Export results", "filepath=[" + output_dir + current_root_stack_name + "_" + extension_filtered_output + ".csv] fileformat=[CSV (comma separated)] " + 
		"id=true frame=true sigma=true chi2=true bkgstd=true intensity=true saveprotocol=true offset=true uncertainty=true y=true x=true");

	wait(20000);

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + current_root_stack_name + "_" + extension_filtered_output + ".tif");
		close(current_root_stack_name + "_" + extension_filtered_output + ".tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + current_root_stack_name + "_" + extension_filtered_output + ".tif");
		close(current_root_stack_name + "_" + extension_filtered_output + ".tif");
	}

	print(f1,"File: " + stacklist_all[n] + " --> data filtering completed.\n");

	run("Show results table", "action=reset");

	} // end of the filtering loop

	close(stacklist_all[n]);

	} // end of the restricted loading loop for tif file

	} // end of the detection + analysis of one tif file

	// Final message within the log window

	print(f1,"\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"ThunderSTORM batch processor has finished to process your files.\n");

	// Save the content of the log window for future reference

	selectWindow("Log_file");
	saveAs("Text", datapaths+"Log_file_ThunderSTORM_processing");

	// Final message within the status bar

	showStatus("ThunderSTORM batch processor has finished to process your files.");

	} // End of MODE 1

	// ----------- MODE 2: DETECT AND FILTER FROM THE LIF STACKS -----------------------------------------------------------------------------------------------------------------------------------------------

	if(gui_choice == "Detection & post-processing (LIF files)") {

	// Load the source folder

		datapaths = getDirectory("Choose directory where your stacks are stored");

	// Create an array with the name of the stacks to analyse

		stacklist_all = getFileList(datapaths);
		number_of_files = lengthOf(stacklist_all);
		stackextensionlist=newArray(stacklist_all.length);

	// Create an array for the extensions of the files

		for (i=0; i<stacklist_all.length; i++) {
			length_stack=lengthOf(stacklist_all[i]);
			stackextensionlist[i]=substring(stacklist_all[i],length_stack-4,length_stack);
		}

		number_of_lif = 0;

		for (n=0; n<stackextensionlist.length; n++) {
			if (stackextensionlist[n] == ".lif") {
				number_of_lif++;
			}
		}
		if(number_of_lif == 0) {exit("This folder doesn't contain any lif file!");} // Exit if no file detected

	// Creation of the dialogue box

		Dialog.create("ThunderSTORM Batch Processor");
		Dialog.addMessage("ThunderSTORM Batch Processor " + current_version_script);
		Dialog.addMessage("Source folder: " + datapaths + " with " + number_of_lif + " lif files.");
		if(gui_twocolours == true) {
		Dialog.addCheckbox("Image warping [you will provide the transformation matrice in the next step]", true);
		Dialog.addString("           Keyword for channel to warp:", "green", 25);
		Dialog.addCheckbox("Inverted drift correction for 1st channel acquired", false);
		Dialog.addString("           Keyword for channel to reverse:", "green", 25);
		}
		Dialog.addMessage("Detection parameters to use:");
		Dialog.addMessage("Filter: Wavelet filter (B-Spline)");
		Dialog.addNumber("           B-Spline order", 3, 0, 25,"");
		Dialog.addNumber("           B-Spline scale", 2.0, 0, 25,"");
		Dialog.addMessage("Detector: Local maximum");
		Dialog.addString("           Peak intensity threshold", "2*std(Wave.F1)", 25);
		Dialog.addChoice("Connectivity", connectivity_array, "8-neighbourhood");
		Dialog.addMessage("Estimator: PSF: Integrated Gaussian");
		Dialog.addNumber("           Fitting radius [px]", 5, 0, 25,"");
		Dialog.addChoice("Method", method_array, "Weighted Least squares");
		Dialog.addString("           Initial sigma [px]", 1.6, 25);
		Dialog.addMessage("");
		Dialog.addMessage("Post-processing:");
		Dialog.addCheckbox("No filtering at all (only detection)", true);
		Dialog.addCheckbox("Filtering", false);
		Dialog.addString("Filtering string:", "intensity>500 & sigma>10 & uncertainty<50", 25);
		Dialog.addCheckbox("Drift correction by cross-correlation", false);
		Dialog.addNumber("           Number of bins:", 5, 0, 25,"");
		Dialog.addNumber("            Magnification:", 3, 0, 25,"");
		Dialog.addCheckbox("Save the drift correction plot", true);
		Dialog.addCheckbox("Merging", false);
		Dialog.addNumber("           Distance threshold [nm]:", 10, 0, 25,"");
		Dialog.addNumber("           Number of dark frames:", 0, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addMessage("Visualization:");
		Dialog.addChoice("Select rendering method", visualisation_array, "Averaged shifted histograms (2D)");
		Dialog.addNumber("           Magnification:", 10, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addChoice("Save output", save_array, "In the source folder");
		Dialog.addString("           Extension for filtered outputs:", "filtered", 25);

		Dialog.show();

		if(gui_twocolours == true) {
		channel_warping = Dialog.getCheckbox();
		channel_warping_keyword = Dialog.getString();
		inverted_drift_correction = Dialog.getCheckbox();
		inverted_drift_correction_keyword = Dialog.getString();
		}
		wavelet_order = Dialog.getNumber();
		wavelet_scale = Dialog.getNumber();
		peak_threshold = Dialog.getString();
		connectivity = Dialog.getChoice();
		fitting_radius = Dialog.getNumber();
		fitting_method = Dialog.getChoice();
		fitting_initial_sigma = Dialog.getString();
		
		cancel_filtering = Dialog.getCheckbox();
		do_filtering = Dialog.getCheckbox();
		filtering_string = Dialog.getString();
		do_driftcorrection = Dialog.getCheckbox();
		drift_correction_bins = Dialog.getNumber();
		drift_correction_magnification = Dialog.getNumber();
		save_driftcorrection_plot = Dialog.getCheckbox();
		do_merging = Dialog.getCheckbox();
		merging_distance = Dialog.getNumber();
		merging_offframes = Dialog.getNumber();
		visualization_choice = Dialog.getChoice();
		magnification_scale = Dialog.getNumber();
		saving_location_choice = Dialog.getChoice();
		extension_filtered_output = Dialog.getString();

	// Find the warp file

	if (channel_warping == true) { transformation_file_path=File.openDialog("Select a warp file"); }

	// Create and populate information for the log file

		f1 = "[Log_file]";
		run("Text Window...", "name="+f1+" width=90 height=40");

		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"ThunderSTORM batch processor " + current_version_script + "\n");
		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"\n");
		print(f1,"Source folder: " + datapaths + " contains " + number_of_lif + " stacks.\n");
		if (channel_warping == true) { print(f1,"Image warping will be applied to all stacks with the keyword \"" + channel_warping_keyword + "\" using the transformation file " + transformation_file_path + ".\n"); }
		print(f1,"Image filtering: Wavelet filter with order = " + wavelet_order + " and scale = " + wavelet_scale + ".\n");
		print(f1,"Approximate localisation of molecules: Local maximum method with a peak intensity threshold of " + peak_threshold + " and a connectivity of " + connectivity + ".\n");
		print(f1,"Sub-pixel localisation of molecules: PSF Integrated Gaussian method using " + fitting_method + " fitting with a fitting radius of " + fitting_radius + " px and an initial sigma of " + fitting_initial_sigma + " px.\n");
		if (cancel_filtering == true) { print(f1,"No post-processing selected.\n"); }
		if (do_filtering == true) { print(f1,"Filtering string applied to the data table: " + filtering_string +".\n"); }
		if (do_driftcorrection == true) { print(f1,"Drift-correction applied with " + drift_correction_bins + " bins and a magnification scale of " + drift_correction_magnification + ".\n"); }
		if (do_merging == true) { print(f1,"Events detected within " + merging_distance + "nm and with " + merging_offframes + " off-frame maximum will be merged.\n"); }

	// Shows up the camera settings window to allow the user to verify the settings

		print(f1,"\nPlease review your camera settings.\n");
		run("Camera setup");

	// Final warning

		print(f1,"Beginning of the batch processing.\n");

	// Beginning of the main loop for one lif file

		for (n=0; n<stackextensionlist.length; n++) {

			if (stackextensionlist[n] == ".lif") {

	// Select the next lif file to analyse and set the destination folder

				file_path=datapaths+stacklist_all[n];

				file_name=File.getName(file_path);
				file_path_length=lengthOf(file_path);
				file_name_length=lengthOf(file_name);
				file_dir=substring(file_path,0,file_path_length-file_name_length);
				file_shortname=substring(file_name,0,file_name_length-4);

				if(saving_location_choice == "In the source folder") {
					output_dir=file_dir;
				}

				if(saving_location_choice == "In a subfolder of the source folder") {
					output_dir=file_dir+file_shortname+File.separator;
					File.makeDirectory(output_dir);
				}

				if(saving_location_choice == "In a folder next to the source folder") {
					output_dir=File.getParent(file_path);
					output_dir=output_dir+"_"+file_shortname+File.separator;
					File.makeDirectory(output_dir);
				}

				if(saving_location_choice == "Somewhere else") {
					if (first_stack ==1) {
						output_dir=getDirectory("Choose the folder to save the files");
						first_stack++; // This allows this loop to run only once to select the destination folder
					}
				}

	run("Bio-Formats Macro Extensions"); // Start BioFormats and get series number in lif file
	Ext.setId(file_path);
	Ext.getSeriesCount(series_count);
	series_names=newArray(series_count);

	for (i=0; i<series_count; i++) {

	Ext.setSeries(i);						// Set the current series
	Ext.getEffectiveSizeC(channel_count);	// Count the number of channels per series (should always be one, in our case)
	series_names[i]="";						// Create an empty variable to store the names
	Ext.getSeriesName(series_names[i]);     // Get the name of the series
	Ext.getSizeT(series_frames);            // Count the number of frames per series

	criterionA = indexOf(series_names[i],"GSD");	// Analyse the naming of the series to find THE ONE
	criterionB = indexOf(series_names[i],"_el_");	// Analyse the naming of the series to find THE ONE

	if(criterionA != -1 && criterionB == -1) { // Load and analyse only the series that matches both criterions

		run("Bio-Formats Importer", "open=["+ file_path + "] view=[Standard ImageJ] stack_order=Default series_"+d2s(i+1,0));

	old_stack_name = stacklist_all[n] + " - " + series_names[i];		// Create the string to call the series stack that has just been loaded

	new_short_stack_name = replace(stacklist_all[n], '.lif', '');		// Remove the ugly lif extension from the lif filename
	new_stack_name = new_short_stack_name + " - " + series_names[i];	// Append to the lif-free filename the series name

	selectWindow(old_stack_name);										// Call the opened stack
	rename(new_stack_name);												// Rename with the lif-free name

	progression_index++;

	print(f1,"\nFile " + progression_index + " out of " + number_of_lif + ": " + stacklist_all[n] + " with " + series_count + " series. Loaded series: " + series_names[i] + " with " + series_frames + " frames.\n");

	// Apply the image warping if required, check that the keyword is found and add an extension to the output file
		
	if(channel_warping == true) {

		criterionC = indexOf(stacklist_all[n],channel_warping_keyword);	// Analyse the naming of the tif file to find if it contains the keyword for warping

		if(criterionC != -1) {
			print(f1,"File: " + new_stack_name + " --> image warping in progress...\n");

			run("MultiStackReg", "action_1=[Load Transformation File] file_1=" + transformation_file_path + " stack_2=None action_2=Ignore file_2=[] transformation=Affine");
			print(f1,"File: " + new_stack_name + " --> image warping completed.\n");
		} else {
			print(f1,"The keyword for image warping hasn't been found in this stack.\n");
		}

	}

	print(f1,"File: " + new_stack_name + " --> detection in progress...\n");

	// ThunderSTORM detection run

	run("Run analysis", "filter=[Wavelet filter (B-Spline)] scale="+ wavelet_scale + " order=" + wavelet_order + " " +
	"detector=[Local maximum] connectivity=" + connectivity + " threshold=" + peak_threshold + " " +
	"estimator=[PSF: Integrated Gaussian] sigma=" + fitting_initial_sigma + " method=[" + fitting_method + "] " +
	"full_image_fitting=false fitradius=" + fitting_radius + " mfaenabled=false renderer=[No Renderer]");

	run("Show results table");

	run("Export results", "filepath=[" + output_dir + new_stack_name + "_allevents.csv] fileformat=[CSV (comma separated)] " + 
		"id=true frame=true sigma=true chi2=true bkgstd=true intensity=true saveprotocol=true offset=true uncertainty=true y=true x=true");

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + new_stack_name + "_allevents.tif");
		close(new_stack_name + "_allevents.tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + new_stack_name + "_allevents.tif");
		close(new_stack_name + "_allevents.tif");
	}

	print(f1,"File: " + new_stack_name + " --> detection completed.\n");

	// Filtering loop (nested within detection loop)

	if (cancel_filtering == false) { // Skip the loop if user didn't request any filtering step

		print(f1,"File: " + new_stack_name + " --> data filtering in progress...\n");

	if (do_filtering == true) {
		filtering_command = "run(\"Show results table\", \"action=filter formula=[" + filtering_string + "]\")";
		eval(filtering_command);
		wait(15000);
	}		// End of filtering step

	if (do_driftcorrection == true) {
		run("Show results table", "action=drift magnification=" + drift_correction_magnification + " save=false showcorrelations=false method=[Cross correlation] steps=" + drift_correction_bins);
		wait(5000);
		selectWindow("Drift");
		if (save_driftcorrection_plot == true) {
			saveAs("Tiff", output_dir + new_stack_name + "_" + extension_filtered_output + "_driftplot.tif");
			close(new_stack_name + "_" + extension_filtered_output + "_driftplot.tif");
			};
		else {
			close("Drift");
			};
		wait(15000);
	}		// End of drift correction step

	if (do_merging == true) {
		run("Show results table", "action=merge offframes=" + merging_offframes + " zcoordweight=0.1 dist=" + merging_distance);
		wait(90000);
	}		// End of merging step

	run("Export results", "filepath=[" + output_dir + new_stack_name + "_" + extension_filtered_output + ".csv] fileformat=[CSV (comma separated)] " + 
		"id=true frame=true sigma=true chi2=true bkgstd=true intensity=true saveprotocol=true offset=true uncertainty=true y=true x=true");

	wait(20000);

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + new_stack_name + "_" + extension_filtered_output + ".tif");
		close(new_stack_name + "_" + extension_filtered_output + ".tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		wait(5000);
		saveAs("Tiff", output_dir + new_stack_name + "_" + extension_filtered_output + ".tif");
		close(new_stack_name + "_" + extension_filtered_output + ".tif");
	}

	print(f1,"File: " + new_stack_name + " --> data filtering completed.\n");

	run("Show results table", "action=reset");

	} // end of the filtering loop

	close(new_stack_name);

	} // end of the restricted loading loop for series that matches criterion

	} // end of the restricted loading loop for lif file

	} // end of the detection + analysis of one lif file

	}

	// Final message within the log window

	print(f1,"\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"ThunderSTORM batch processor has finished to process your files.\n");

	// Save the content of the log window for future reference

	selectWindow("Log_file");
	saveAs("Text", datapaths+"Log_file_ThunderSTORM_processing");

	// Final message within the status bar

	showStatus("ThunderSTORM batch processor has finished to process your files.");

	} // End of MODE 2

	// ----------------- MODE 3: FILTERING ONLY ----------------------------------------------------------------------------------------------------------------------------------------------------------------

	if(gui_choice == "Post-processing (CSV files)") {

	// Load the source folder

		datapaths = getDirectory("Choose directory where your csv files are stored");

	// Create an array with the name of the stacks to analyse

		filelist_all = getFileList(datapaths);
		number_of_files = lengthOf(filelist_all);
		fileextensionlist=newArray(filelist_all.length);

	// Create an array for the extensions of the files

		for (i=0; i<filelist_all.length; i++) {
			length_stack=lengthOf(filelist_all[i]);
			fileextensionlist[i]=substring(filelist_all[i],length_stack-4,length_stack);
		}

		number_of_csv = 0;
		for (n=0; n<fileextensionlist.length; n++) {
			if (fileextensionlist[n] == ".csv") { number_of_csv++; }
		}
		if(number_of_csv == 0) {exit("This folder doesn't contain any csv file!");} // Exit if no file detected

	// Creation of the dialogue box

		Dialog.create("ThunderSTORM Batch Processor");
		Dialog.addMessage("ThunderSTORM Batch Processor " + current_version_script);
		Dialog.addMessage("Source folder: " + datapaths);
		Dialog.addMessage("Number of csv files detected: " + number_of_csv);
		Dialog.addMessage("Post-processing:");
		Dialog.addMessage("");
		Dialog.addCheckbox("Filtering", false);
		Dialog.addString("Filtering string:", "intensity>500 & sigma>10 & uncertainty<50", 25);
		Dialog.addMessage("");
		Dialog.addCheckbox("Drift correction by cross-correlation", false);
		Dialog.addNumber("           Number of bins:", 5, 0, 25,"");
		Dialog.addNumber("            Magnification:", 3, 0, 25,"");
		Dialog.addCheckbox("Save the drift correction plot", true);
		Dialog.addMessage("");
		Dialog.addCheckbox("Merging", false);
		Dialog.addNumber("           Distance threshold [nm]:", 10, 0, 25,"");
		Dialog.addNumber("           Number of dark frames:", 0, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addMessage("Visualization:");
		Dialog.addMessage("");
		Dialog.addChoice("Select rendering method", visualisation_array, "Averaged shifted histograms (2D)");
		Dialog.addNumber("           Magnification:", 10, 0, 25,"");
		Dialog.addMessage("");
		Dialog.addChoice("Save output", save_array, "In the source folder");
		Dialog.addString("           Extension for filtered outputs:", "filtered", 25);

		Dialog.show();

		do_filtering = Dialog.getCheckbox();
		filtering_string = Dialog.getString();
		do_driftcorrection = Dialog.getCheckbox();
		drift_correction_bins = Dialog.getNumber();
		drift_correction_magnification = Dialog.getNumber();
		save_driftcorrection_plot = Dialog.getCheckbox();
		do_merging = Dialog.getCheckbox();
		merging_distance = Dialog.getNumber();
		merging_offframes = Dialog.getNumber();
		visualization_choice = Dialog.getChoice();
		magnification_scale = Dialog.getNumber();
		saving_location_choice = Dialog.getChoice();
		extension_filtered_output = Dialog.getString();

		if (do_filtering == false && do_driftcorrection == false && do_merging == false) {
			exit("You must select at least one step for data filtering!");
		}

	// Create and populate information for the log file

		f1 = "[Log_file]";
		run("Text Window...", "name="+f1+" width=90 height=40");

		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"ThunderSTORM batch processor " + current_version_script + "\n");
		print(f1,"----------------------------------------------------------------------------------\n");
		print(f1,"\n");
		print(f1,"Source folder: " + datapaths + " contains " + number_of_csv + " data tables.\n");
		if (do_filtering == true) { print(f1,"Filtering string applied to the data table: " + filtering_string +".\n"); }
		if (do_driftcorrection == true) { print(f1,"Drift-correction applied with " + drift_correction_bins + " bins and a magnification scale of " + drift_correction_magnification + ".\n"); }
		if (do_merging == true) { print(f1,"Events detected within " + merging_distance + "nm and with " + merging_offframes + " off-frame maximum will be merged.\n"); }

	// Shows up the camera settings window to allow the user to verify the settings

		print(f1,"\nPlease review your camera settings.\n");
		run("Camera setup");

	// Final warning

		print(f1,"Beginning of the batch processing.\n\n");

	// Main nested analysis loop

		for (n=0; n<fileextensionlist.length; n++) {

	if (fileextensionlist[n] == ".csv") { // Beginning of the restricted loading condition for csv files

		file_path=datapaths+filelist_all[n];
		file_name=File.getName(file_path);
		file_path_length=lengthOf(file_path);
		file_name_length=lengthOf(file_name);
		file_dir=substring(file_path,0,file_path_length-file_name_length);
	file_shortname=substring(file_name,0,file_name_length-4);			// Another way to remove the file extension

	if(saving_location_choice == "In the source folder") {
		output_dir=file_dir;
	}

	if(saving_location_choice == "In a subfolder of the source folder") {
		output_dir=file_dir+file_shortname+File.separator;
		File.makeDirectory(output_dir);
	}

	if(saving_location_choice == "In a folder next to the source folder") {
		output_dir=File.getParent(file_path);
		output_dir=output_dir+"_"+file_shortname+File.separator;
		File.makeDirectory(output_dir);
	}

	if(saving_location_choice == "Somewhere else") {
		if (first_stack ==1) {
			output_dir=getDirectory("Choose the folder to save the files");
	first_stack++; // This allows this loop to run only once to select the destination folder
	}
	}

	// Analysis (main nested loop)

	print(f1,"File: " + filelist_all[n] + ".\n");

	run("Import results", "append=false startingframe=1 rawimagestack= filepath=[" + file_path + "] livepreview=false fileformat=[CSV (comma separated)]"); // Import the csv file

	current_root_file_name = replace(filelist_all[n], '.csv', '');	// Extract the filename without the csv extension 

	if (do_filtering == true) {
		filtering_command = "run(\"Show results table\", \"action=filter formula=[" + filtering_string + "]\")";
		eval(filtering_command);
		wait(15000);
	}		// End of filtering step

	if (do_driftcorrection == true) {
		run("Show results table", "action=drift magnification=" + drift_correction_magnification + " save=false showcorrelations=false method=[Cross correlation] steps=" + drift_correction_bins);
		wait(5000);
		selectWindow("Drift");
		if (save_driftcorrection_plot == true) {
			saveAs("Tiff", output_dir + current_root_file_name +  "_" + extension_filtered_output + "_driftplot.tif");
			close(current_root_file_name + "_" + extension_filtered_output + "_driftplot.tif");
			};
		else {
			close("Drift");
			};
		wait(15000);
	}		// End of drift correction step

	if (do_merging == true) {
		run("Show results table", "action=merge offframes=" + merging_offframes + " zcoordweight=0.1 dist=" + merging_distance);
		wait(90000);
	}		// End of merging step

	run("Export results", "filepath=[" + output_dir + current_root_file_name + "_" + extension_filtered_output + ".csv] fileformat=[CSV (comma separated)] " + 
		"id=true frame=true sigma=true chi2=true bkgstd=true intensity=true saveprotocol=true offset=true uncertainty=true y=true x=true");

	wait(20000);

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		saveAs("Tiff", output_dir + current_root_file_name + "_" + extension_filtered_output + ".tif");
		close(current_root_file_name + "_" + extension_filtered_output + ".tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		saveAs("Tiff", output_dir + current_root_file_name + "_" + extension_filtered_output + ".tif");
		close(current_root_file_name + "_" + extension_filtered_output + ".tif");
	}

	print(f1,"File " + current_root_file_name + "_" + extension_filtered_output + " analysed and saved.\n");

	run("Show results table", "action=reset");	// safety measure to avoid the odd listing of past filtering steps in the protocol

	} // End of the restricted condition for csv file

	} // End of the for loop (n) for loading the csv files

	// Final message within the log window

	print(f1,"\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"ThunderSTORM batch processor has finished to process your files.\n");

	// Save the content of the log window for future reference

	selectWindow("Log_file");
	saveAs("Text", datapaths + "Log_file_ThunderSTORM_processing");

	// Final message within the status bar

	showStatus("ThunderSTORM batch processor has finished to process your files.");

	} // End of MODE 3

	// ----------------- MODE 4: PLOTTING HR IMAGES ONLY -------------------------------------------------------------------------------------------------------------------------------------------------------

	if(gui_choice == "Visualisation (CSV files)") { // beginning of mode 4

	datapaths = getDirectory("Choose directory where your csv files are stored");	// Load the source folder

	// Create an array with the name of the stacks to analyse

	filelist_all = getFileList(datapaths);
	number_of_files = lengthOf(filelist_all);
	fileextensionlist=newArray(filelist_all.length);

	// Create an array for the extensions of the files

	for (i=0; i<filelist_all.length; i++) {
		length_stack=lengthOf(filelist_all[i]);
		fileextensionlist[i]=substring(filelist_all[i],length_stack-4,length_stack);
	}

	number_of_csv = 0;
	for (n=0; n<fileextensionlist.length; n++) {
		if (fileextensionlist[n] == ".csv") { number_of_csv++; }
	}
	if(number_of_csv == 0) {exit("This folder doesn't contain any csv file!");} // Exit if no file detected

	// Creation of the dialogue box

	Dialog.create("ThunderSTORM Batch Processor");
	Dialog.addMessage("ThunderSTORM Batch Processor " + current_version_script);
	Dialog.addMessage("Source folder: " + datapaths);
	Dialog.addMessage("Number of csv files detected: " + number_of_csv);
	Dialog.addMessage("Visualization:");
	Dialog.addMessage("");
	Dialog.addChoice("Select rendering method", visualisation_array, "Averaged shifted histograms (2D)");
	Dialog.addNumber("           Magnification:", 10, 0, 25,"");
	Dialog.addMessage("");
	Dialog.addChoice("Save output", save_array, "In the source folder");
	Dialog.addString("           Extension for outputs:", "SR_image", 25);

	Dialog.show();

	visualization_choice = Dialog.getChoice();
	magnification_scale = Dialog.getNumber();
	saving_location_choice = Dialog.getChoice();
	extension_filtered_output = Dialog.getString();

	// Create and populate information for the log file

	f1 = "[Log_file]";
	run("Text Window...", "name=" + f1 + " width=90 height=40");

	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"ThunderSTORM batch processor " + current_version_script + "\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"Source folder: " + datapaths + " contains " + number_of_csv + " data tables.\n");

	print(f1,"\nPlease review your camera settings.\n");
	run("Camera setup"); // Shows up the camera settings window to allow the user to verify the settings

	print(f1,"Beginning of the batch processing.\n"); // final warning

	// Main loop

	for (n=0; n<fileextensionlist.length; n++) {	// Main loop

		if (fileextensionlist[n] == ".csv") {

			file_path=datapaths+filelist_all[n];

			file_name=File.getName(file_path);
			file_path_length=lengthOf(file_path);
			file_name_length=lengthOf(file_name);
			file_dir=substring(file_path,0,file_path_length-file_name_length);
			file_shortname=substring(file_name,0,file_name_length-4);

			if(saving_location_choice == "In the source folder") {
				output_dir=file_dir;
			}

			if(saving_location_choice == "In a subfolder of the source folder") {
				output_dir=file_dir+file_shortname+File.separator;
				File.makeDirectory(output_dir);
			}

			if(saving_location_choice == "In a folder next to the source folder") {
				output_dir=File.getParent(file_path);
				output_dir=output_dir+"_"+file_shortname+File.separator;
				File.makeDirectory(output_dir);
			}

			if(saving_location_choice == "Somewhere else") {
				if (first_stack ==1) {
					output_dir=getDirectory("Choose the folder to save the files");
	first_stack++; // This allows this loop to run only once to select the destination folder
	}
	}

	// Visualisation

	print(f1,"\nData table: " + filelist_all[n] + " loaded.\n");

	run("Import results", "append=false startingframe=1 rawimagestack= filepath=[" + file_path + "] livepreview=false fileformat=[CSV (comma separated)]");

	current_root_file_name = replace(filelist_all[n], '.csv', '');

	if(visualization_choice == "Averaged shifted histograms (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Averaged shifted histograms] magnification=" + magnification_scale + " colorizez=true shifts=2 threed=false");
		saveAs("Tiff", output_dir + current_root_file_name + "_" + extension_filtered_output + ".tif");
		close(current_root_file_name + "_" + extension_filtered_output + ".tif");
	}

	if(visualization_choice == "Normalized Gaussian (2D)") {
		run("Visualization", "imleft=0 imtop=0 imwidth=180 imheight=180 renderer=[Normalized Gaussian] magnification=" + magnification_scale + " dxforce=false colorizez=true dx=20.0 threed=false");
		saveAs("Tiff", output_dir + current_root_file_name + "_" + extension_filtered_output + ".tif");
		close(current_root_file_name + "_" + extension_filtered_output + ".tif");
	}

	print(f1,"High resolution image from " + current_root_file_name + "_" + extension_filtered_output + " saved.\n");

	run("Show results table", "action=reset");

	}	// end of the restricted condition for csv files

	} // End of the for loop (n) for loading the csv files

	// Final message within the log window

	print(f1,"\n");
	print(f1,"----------------------------------------------------------------------------------\n");
	print(f1,"\n");
	print(f1,"ThunderSTORM batch processor has finished to process your files.\n");

	// Save the content of the log window for future reference

	selectWindow("Log_file");
	saveAs("Text", datapaths+"Log_file_ThunderSTORM_processing");

	// Final message within the status bar

	showStatus("ThunderSTORM batch processor has finished to process your files.");

	} // End of MODE 4

} // End of the macro
