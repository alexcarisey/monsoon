% %% Clean up

% clc; close all; clear all;

%% Loading the folder

uiwait(msgbox('Please locate the folder containing the csv files','Loading','non-modal'));

choice=0; issue={'none'};

while choice==0;
    
    % Define folder where images are stored
    
    directoryname = uigetdir('', 'Pick the directory containing the CSV files');
    addpath(directoryname);
    cd(directoryname);
    csvfiles = dir(fullfile(directoryname, ...
        '*.csv'));
    csvfiles_numb = size(csvfiles,1);
    
    % Reset the loop if folder is empty
    
    if csvfiles_numb == 0; issue = {'no_file'}; else end
    switch issue{1,1};
        case {'no_file'}
            h = msgbox(sprintf('The source folder is empty'),'Warning','warn');
            uiwait(h);
            clear csvfiles csvfiles_numb directoryname
            issue={'none'};
        case {'none'}
            choice = 1;
    end
    
end

clear choice issue h
fprintf('Folder containing the csv files acquired.\n\n');

%% Variables from the user

PhotonPlotMax = 5000;
SigmaPlotMax = 2000;
UncertaintyPlotMax = 500;
OffsetPlotMax = 500;
BkgstdPlotMax = 500;

PhotonPlotMax_zoom = 1000;
SigmaPlotMax_zoom = 250;
UncertaintyPlotMax_zoom = 100;
OffsetPlotMax_zoom = 100;
BkgstdPlotMax_zoom = 50;

FrameBins = 10;

%% Loop through the CSV files

textprogressbar('Creating reports:   ');
indicator_progress = 100/csvfiles_numb;

for j=1:csvfiles_numb
    
    textprogressbar(indicator_progress);
    
    % Loading the csv datatable
    
    delimiter = ',';
    startRow = 2;
    formatSpec = '%f%f%f%f%f%f%f%f%f%[^\n\r]';
    
    fileID = fopen(csvfiles(j).name,'r');
    dataArray = textscan(fileID, formatSpec, 'Delimiter', delimiter, 'EmptyValue' ,NaN,'HeaderLines' ,startRow-1, 'ReturnOnError', false);
    fclose(fileID);
    
    id = dataArray{:, 1};
    frame = dataArray{:, 2};
    x = dataArray{:, 3};
    y = dataArray{:, 4};
    sigma = dataArray{:, 5};
    intensity = dataArray{:, 6};
    offset = dataArray{:, 7};
    bkgstd = dataArray{:, 8};
    uncertainty = dataArray{:, 9};
    
    clearvars filename delimiter startRow formatSpec fileID dataArray ans;
    
    % Variable from the dataset
    
    FrameMin=1;
    FrameMax=max(frame);
    FrameAxisBins=(FrameMin:1:FrameMax)';
    HistoBins=ceil(FrameMax/FrameBins);
    
    % Calculate frame events histogram
    
    EventCounts=zeros(FrameMax,1);
    for f = 1:FrameMax
        EventCounts(f,1) = numel(find((frame(:,1)) == FrameAxisBins(f,1)));
    end
    
    % Create figure
    
    h01 = figure('Name','Overview of the datatable');
    set(gcf,'position',get(0,'screensize'),'PaperPositionMode','auto');
    
    % Plot frame events histogram
    
    subplot(3,3,[1 2 4 5]);
    scatter(FrameAxisBins(:,1),EventCounts(:,1),'.','k');
    ylim([0 max(EventCounts)]); xlim([0 FrameMax]);
    title('Events per Frame'); xlabel('Frame ID'); ylabel('Events');
    box('on');
    
    % Plot photon histogram
    
    PhotonIndex = find(intensity<PhotonPlotMax);
    PhotonData = intensity(PhotonIndex);
    subplot(3,3,3);
    hist(PhotonData,HistoBins);
    title('Photon Count'); xlabel('Intensity [photons]'); ylabel('Frequency'); xlim([0 PhotonPlotMax]);
    h11 = findobj(gca,'Type','patch'); set(h11,'EdgeColor','b'); rectangle('Position',[0,0,PhotonPlotMax_zoom,max(hist(PhotonData,HistoBins))]);
    PhotonDetail = axes('Position', [.79, .79, .1, .1]);
    hist(PhotonDetail,PhotonData,HistoBins);
    xlim([0 PhotonPlotMax_zoom]);
    h12 = findobj(gca,'Type','patch'); set(h12,'EdgeColor','r');
    
    % Plot sigma histogram
    
    SigmaIndex = find(sigma<SigmaPlotMax);
    SigmaData = sigma(SigmaIndex);
    subplot(3,3,6);
    hist(SigmaData,HistoBins);
    title('Sigma'); xlabel('Sigma [nm]'); ylabel('Frequency'); xlim([0 SigmaPlotMax]);
    h21 = findobj(gca,'Type','patch'); set(h21,'EdgeColor','b'); rectangle('Position',[0,0,SigmaPlotMax_zoom,max(hist(SigmaData,HistoBins))]);
    SigmaDetail = axes('Position', [.79, .49, .1, .1]);
    hist(SigmaDetail,SigmaData,HistoBins);
    xlim([0 SigmaPlotMax_zoom]);
    h22 = findobj(gca,'Type','patch'); set(h22,'EdgeColor','r');
    
    % Plot uncertainty histogram
    
    UncertaintyIndex = find(uncertainty<UncertaintyPlotMax);
    UncertaintyData = uncertainty(UncertaintyIndex);
    subplot(3,3,7);
    hist(UncertaintyData,HistoBins);
    title('Uncertainty'); xlabel('Uncertainty [nm]'); ylabel('Frequency'); xlim([0 UncertaintyPlotMax]);
    h31 = findobj(gca,'Type','patch'); set(h31,'EdgeColor','b'); rectangle('Position',[0,0,UncertaintyPlotMax_zoom,max(hist(UncertaintyData,HistoBins))]);
    UncertaintyDetail = axes('Position', [.23, .19, .1, .1]);
    hist(UncertaintyDetail,UncertaintyData,HistoBins);
    xlim([0 UncertaintyPlotMax_zoom]);
    h32 = findobj(gca,'Type','patch'); set(h32,'EdgeColor','r');
    
    % Plot backgst histogram
    
    BkgstdIndex = find(bkgstd<BkgstdPlotMax);
    BkgstdData = bkgstd(BkgstdIndex);
    subplot(3,3,8);
    hist(BkgstdData,HistoBins);
    title('Bkgstd'); xlabel('Bkgstd [photons]'); ylabel('Frequency'); xlim([0 BkgstdPlotMax]);
    h41 = findobj(gca,'Type','patch'); set(h41,'EdgeColor','b'); rectangle('Position',[0,0,BkgstdPlotMax_zoom,max(hist(BkgstdData,HistoBins))]);
    BkgstdDetail = axes('Position', [.51, .19, .1, .1]);
    hist(BkgstdDetail,BkgstdData,HistoBins);
    xlim([0 BkgstdPlotMax_zoom]);
    h42 = findobj(gca,'Type','patch'); set(h42,'EdgeColor','r');
    
    % Plot offset histogram
    
    OffsetIndex = find(offset<OffsetPlotMax);
    OffsetData = offset(OffsetIndex);
    subplot(3,3,9);
    hist(OffsetData,HistoBins);
    title('Offset'); xlabel('Offset [photons]'); ylabel('Frequency'); xlim([0 OffsetPlotMax]);
    h51 = findobj(gca,'Type','patch'); set(h51,'EdgeColor','b'); rectangle('Position',[0,0,OffsetPlotMax_zoom,max(hist(OffsetData,HistoBins))]);
    OffsetDetail = axes('Position', [.79, .19, .1, .1]);
    hist(OffsetDetail,OffsetData,HistoBins);
    xlim([0 OffsetPlotMax_zoom]);
    h52 = findobj(gca,'Type','patch'); set(h52,'EdgeColor','r');
    
    % Create the output filename
    
    export_name = strcat(csvfiles(j).name(1:end-4),'_overview.png');
    print('-dpng',export_name);
    
    close(h01);
    
    indicator_progress = indicator_progress + (100/csvfiles_numb);
    
end

%% Conclusion

textprogressbar(' Done');