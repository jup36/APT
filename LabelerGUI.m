function varargout = LabelerGUI(varargin)
% Labeler GUI

% Last Modified by GUIDE v2.5 08-Nov-2017 11:28:24

% Begin initialization code - DO NOT EDIT
gui_Singleton = 0;
% AL20151104: 'dpi-aware' MATLAB graphics introduced in R2015b have trouble
% with .figs created in previous versions. Did significant testing across
% MATLAB versions and platforms and behavior appears at least mildly 
% wonky-- couldn't figure out a clean solution. For now use two .figs
if ispc && ~verLessThan('matlab','8.6') % 8.6==R2015b
  gui_Name = 'LabelerGUI_PC_15b';
elseif isunix
  gui_Name = 'LabelerGUI_lnx';
else
  gui_Name = 'LabelerGUI_PC_14b';
end
gui_State = struct('gui_Name',       gui_Name, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @LabelerGUI_OpeningFcn, ...
                   'gui_OutputFcn',  @LabelerGUI_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1}) && exist(varargin{1}), %#ok<EXIST>
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

function LabelerGUI_OpeningFcn(hObject,eventdata,handles,varargin) 

if verLessThan('matlab','8.4')
  error('LabelerGUI:ver','LabelerGUI requires MATLAB version R2014b or later.');
end

hObject.Name = 'APT';
hObject.HandleVisibility = 'on';

% delete unused stuff from toolbar
h = findall(hObject,'type','uitoolbar');
KEEP = {'Exploration.Rotate' 'Exploration.Pan' 'Exploration.ZoomOut' ...
  'Exploration.ZoomIn'};
hh = findall(h,'-not','type','uitoolbar','-property','Tag');
for h=hh(:)'
  if ~any(strcmp(h.Tag,KEEP))
    delete(h);
  end
end

% reinit uicontrol strings etc from GUIDE for cosmetic purposes
set(handles.txPrevIm,'String','');
set(handles.edit_frame,'String','');
set(handles.txStatus,'String','');
set(handles.txUnsavedChanges,'Visible','off');
set(handles.txLblCoreAux,'Visible','off');
set(handles.pnlSusp,'Visible','off');

handles.pnlSusp.Visible = 'off';

handles=LabelerTooltips(handles); % would be cool to have a toggle to NOT do this for advanced users -- the tooltips are annoying as shit once you know what you're doing.

PURP = [80 31 124]/256;
handles.tbTLSelectMode.BackgroundColor = PURP;

handles.output = hObject;

handles.labelerObj = varargin{1};
varargin = varargin(2:end); %#ok<NASGU>

handles.menu_file_export_labels_table = uimenu('Parent',handles.menu_file_importexport,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_file_export_labels_table_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Export Labels as Single Table',...
  'Tag','menu_file_export_labels_table',...
  'Checked','off',...
  'Visible','on');
moveMenuItemAfter(handles.menu_file_export_labels_table,...
  handles.menu_file_export_labels_trks);

% Label/Setup menu
mnuLblSetup = handles.menu_labeling_setup;
mnuLblSetup.Position = 3;
if isprop(mnuLblSetup,'Text')
  mnuLblSetup.Text = 'Label';
else
  mnuLblSetup.Label = 'Label';
end

handles.menu_setup_multiview_calibrated_mode_2 = uimenu(...
  'Parent',handles.menu_labeling_setup,...
  'Label','Multiview Calibrated',...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_setup_multiview_calibrated_mode_2_Callback',hObject,eventdata,guidata(hObject)),...
  'Tag','menu_setup_multiview_calibrated_mode_2');  
delete(handles.menu_setup_multiview_calibrated_mode);
handles.menu_setup_multiview_calibrated_mode = [];
delete(handles.menu_setup_tracking_correction_mode);
handles.menu_setup_tracking_correction_mode = [];
delete(handles.menu_setup_createtemplate);
handles.menu_setup_label_overlay_montage = uimenu('Parent',handles.menu_labeling_setup,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_setup_label_overlay_montage_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Label Overlay Montage',...
  'Tag','menu_setup_label_overlay_montage',...
  'Visible','on');
handles.menu_setup_label_overlay_montage_trx_centered = uimenu('Parent',handles.menu_labeling_setup,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_setup_label_overlay_montage_trx_centered_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Label Overlay Montage (trx centered)',...
  'Tag','menu_setup_label_overlay_montage_trx_centered',...
  'Visible','on');
handles.menu_setup_set_nframe_skip = uimenu('Parent',handles.menu_labeling_setup,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_setup_set_nframe_skip_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Set Frame Increment',...
  'Tag','menu_setup_set_nframe_skip',...
  'Visible','on');
handles.menu_setup_streamlined = uimenu('Parent',handles.menu_labeling_setup,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_setup_streamlined_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Streamlined',...
  'Tag','menu_setup_streamlined',...
  'Checked','off',...
  'Visible','on');

LABEL_MENU_ORDER = {
   'menu_setup_sequential_mode'
   'menu_setup_template_mode'
   'menu_setup_highthroughput_mode'
   'menu_setup_multiview_calibrated_mode_2'   
   'menu_setup_label_overlay_montage'
   'menu_setup_label_overlay_montage_trx_centered'
   'menu_setup_set_labeling_point'
   'menu_setup_set_nframe_skip'
   'menu_setup_streamlined'
   'menu_setup_load_calibration_file'
   'menu_setup_lock_all_frames'
   'menu_setup_unlock_all_frames'};
menuReorder(handles.menu_labeling_setup,LABEL_MENU_ORDER);
handles.menu_setup_label_overlay_montage.Separator = 'on';
handles.menu_setup_set_labeling_point.Separator = 'on';
handles.menu_setup_streamlined.Separator = 'on';
handles.menu_setup_load_calibration_file.Separator = 'off';

handles.menu_view_show_bgsubbed_frames = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_show_bgsubbed_frames_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Show background subtracted frames',...
  'Tag','menu_view_show_bgsubbed_frames',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_show_bgsubbed_frames,...
  handles.menu_view_gammacorrect);

handles.menu_view_rotate_video_target_up = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_rotate_video_target_up_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Rotate video so target always points up',...
  'Tag','menu_view_rotate_video_target_up',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_rotate_video_target_up,...
  handles.menu_view_trajectories_centervideoontarget);

handles.menu_view_hide_predictions = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_hide_predictions_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Hide predictions',...
  'Tag','menu_view_hide_predictions',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_hide_predictions,handles.menu_view_hide_labels);
handles.menu_view_hide_imported_predictions = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_hide_imported_predictions_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Hide imported predictions',...
  'Tag','menu_view_hide_imported_predictions',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_hide_imported_predictions,handles.menu_view_hide_predictions);

handles.menu_view_show_replicates = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_show_replicates_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Show predicted replicates',...
  'Tag','menu_view_show_replicates',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_show_replicates,handles.menu_view_hide_imported_predictions);
handles.menu_view_hide_trajectories = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_hide_trajectories_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Hide trajectories',...
  'Tag','menu_view_hide_trajectories',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_hide_trajectories,handles.menu_view_show_replicates);
handles.menu_view_plot_trajectories_current_target_only = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_plot_trajectories_current_target_only_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Plot trajectories only for current target',...
  'Tag','menu_view_plot_trajectories_current_target_only',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_plot_trajectories_current_target_only,...
  handles.menu_view_hide_trajectories);

delete(handles.menu_view_trajectories);

handles.menu_view_show_tick_labels = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_show_tick_labels_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Show tick labels',...
  'Tag','menu_view_show_tick_labels',...
  'Separator','on',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_show_tick_labels,...
  handles.menu_view_plot_trajectories_current_target_only);
handles.menu_view_show_grid = uimenu('Parent',handles.menu_view,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_view_show_grid_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Show grid',...
  'Tag','menu_view_show_grid',...
  'Checked','off');
moveMenuItemAfter(handles.menu_view_show_grid,handles.menu_view_show_tick_labels);
% handles.menu_view_show_3D_axes = uimenu('Parent',handles.menu_view,...
%   'Callback',@(hObject,eventdata)LabelerGUI('menu_view_show_3D_axes_Callback',hObject,eventdata,guidata(hObject)),...
%   'Label','Show/Refresh 3D world axes',...
%   'Tag','menu_view_show_3D_axes',...
%   'Checked','off');
% moveMenuItemAfter(handles.menu_view_show_3D_axes,handles.menu_view_show_grid);

handles.menu_track_setparametersfile.Label = 'Configure tracking parameters';
handles.menu_track_setparametersfile.Callback = @(hObject,eventdata)LabelerGUI('menu_track_setparametersfile_Callback',hObject,eventdata,guidata(hObject));
handles.menu_track_use_all_labels_to_train = uimenu(...
  'Parent',handles.menu_track,...
  'Label','Include all labels in training data',...
  'Tag','menu_track_use_all_labels_to_train',...
  'Separator','on',...
  'Callback',@(h,evtdata)LabelerGUI('menu_track_use_all_labels_to_train_Callback',h,evtdata,guidata(h)));
moveMenuItemAfter(handles.menu_track_use_all_labels_to_train,handles.menu_track_setparametersfile);
handles.menu_track_select_training_data.Label = 'Downsample training data';
handles.menu_track_select_training_data.Visible = 'off';
moveMenuItemAfter(handles.menu_track_select_training_data,handles.menu_track_use_all_labels_to_train);
handles.menu_track_training_data_montage = uimenu(...
  'Parent',handles.menu_track,...
  'Label','Training Data Montage',...
  'Tag','menu_track_training_data_montage',...
  'Callback',@(h,evtdata)LabelerGUI('menu_track_training_data_montage_Callback',h,evtdata,guidata(h)));
moveMenuItemAfter(handles.menu_track_training_data_montage,handles.menu_track_select_training_data);

moveMenuItemAfter(handles.menu_track_track_and_export,handles.menu_track_retrain);

handles.menu_track_trainincremental = handles.menu_track_retrain;
handles = rmfield(handles,'menu_track_retrain');
handles.menu_track_trainincremental.Callback = @(h,edata)LabelerGUI('menu_track_trainincremental_Callback',h,edata,guidata(h));
handles.menu_track_trainincremental.Label = 'Incremental Train';
handles.menu_track_trainincremental.Tag = 'menu_track_trainincremental';
handles.menu_track_trainincremental.Visible = 'off';
%handles.menu_track_track_and_export.Separator = 'off';

handles.menu_track_export_base = uimenu('Parent',handles.menu_track,...
  'Label','Export current tracking results',...
  'Tag','menu_track_export_base');  
moveMenuItemAfter(handles.menu_track_export_base,handles.menu_track_track_and_export);
handles.menu_track_export_current_movie = uimenu('Parent',handles.menu_track_export_base,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_export_current_movie_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Current movie only',...
  'Tag','menu_track_export_current_movie');  
handles.menu_track_export_all_movies = uimenu('Parent',handles.menu_track_export_base,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_export_all_movies_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','All movies',...
  'Tag','menu_track_export_all_movies'); 

handles.menu_track_clear_tracking_results = uimenu('Parent',handles.menu_track,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_clear_tracking_results_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Clear tracking results',...
  'Tag','menu_track_clear_tracking_results');  
moveMenuItemAfter(handles.menu_track_clear_tracking_results,handles.menu_track_export_base);

handles.menu_track_store_full_tracking = uimenu('Parent',handles.menu_track,...
  'Label','Store tracking replicates/iterations',...
  'Tag','menu_track_store_full_tracking');
moveMenuItemAfter(handles.menu_track_store_full_tracking,...
  handles.menu_track_clear_tracking_results);
handles.menu_track_store_full_tracking_dont_store = uimenu(...
  'Parent',handles.menu_track_store_full_tracking,...
  'Label','Don''t store replicates',...
  'Tag','menu_track_store_full_tracking_dont_store',...
  'Checked','on',...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_store_full_tracking_dont_store_Callback',hObject,eventdata,guidata(hObject)));
handles.menu_track_store_full_tracking_store_final_iteration = uimenu(...
  'Parent',handles.menu_track_store_full_tracking,...
  'Label','Store replicates, final iteration only',...
  'Tag','menu_track_store_full_tracking_store_final_iteration',...
  'Checked','off',...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_store_full_tracking_store_final_iteration_Callback',hObject,eventdata,guidata(hObject)));
handles.menu_track_store_full_tracking_store_all_iterations = uimenu(...
  'Parent',handles.menu_track_store_full_tracking,...
  'Label','Store replicates, all iterations',...
  'Tag','menu_track_store_full_tracking_store_all_iterations',...
  'Checked','off',...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_store_full_tracking_store_all_iterations_Callback',hObject,eventdata,guidata(hObject)));

handles.menu_track_view_tracking_diagnostics = uimenu('Parent',handles.menu_track,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_view_tracking_diagnostics_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','View tracking diagnostics',...
  'Tag','menu_track_view_tracking_diagnostics',...
  'Separator','off',...
  'Checked','off');
moveMenuItemAfter(handles.menu_track_view_tracking_diagnostics,handles.menu_track_store_full_tracking);

handles.menu_track_set_labels = uimenu('Parent',handles.menu_track,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_set_labels_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Set manual labels to predicted pose',...
  'Tag','menu_track_set_labels');  

tfBGok = ~isempty(ver('distcomp')) && ~verLessThan('distcomp','6.10');
onoff = onIff(tfBGok);
handles.menu_track_background_predict = uimenu('Parent',handles.menu_track,...
  'Label','Background prediction','Tag','menu_track_background_predict',...
  'Separator','on','Enable',onoff);
moveMenuItemAfter(handles.menu_track_background_predict,...
  handles.menu_track_set_labels);

handles.menu_track_background_predict_start = uimenu(...
  'Parent',handles.menu_track_background_predict,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_background_predict_start_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Start/enable background prediction',...
  'Tag','menu_track_background_predict_start');
handles.menu_track_background_predict_end = uimenu(...
  'Parent',handles.menu_track_background_predict,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_background_predict_end_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Stop background prediction',...
  'Tag','menu_track_background_predict_end');
handles.menu_track_background_predict_stats = uimenu(...
  'Parent',handles.menu_track_background_predict,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_track_background_predict_stats_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Background prediction stats',...
  'Tag','menu_track_background_predict_stats');

handles.menu_help_about = uimenu(...
  'Parent',handles.menu_help,...
  'Label','About',...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_help_about_Callback',hObject,eventdata,guidata(hObject)),...
  'Tag','menu_help_about');  
moveMenuItemBefore(handles.menu_help_about,handles.menu_help_labeling_actions);

% Go menu
handles.menu_go = uimenu('Parent',handles.figure,'Position',4,'Label','Go');
handles.menu_go_targets_summary = uimenu('Parent',handles.menu_go,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_go_targets_summary_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Switch targets',...
  'Tag','menu_go_targets_summary',...
  'Separator','off',...
  'Checked','off');
handles.menu_go_nav_prefs = uimenu('Parent',handles.menu_go,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_go_nav_prefs_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Navigation preferences',...
  'Tag','menu_go_nav_prefs',...
  'Separator','off',...
  'Checked','off');

% Evaluate menu
handles.menu_evaluate = uimenu('Parent',handles.figure,'Position',6,'Label','Evaluate');
handles.menu_evaluate_crossvalidate = uimenu('Parent',handles.menu_evaluate,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_evaluate_crossvalidate_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Cross validate',...
  'Tag','menu_evaluate_crossvalidate',...
  'Separator','off',...
  'Checked','off');
handles.menu_evaluate_gtmode = uimenu('Parent',handles.menu_evaluate,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_evaluate_gtmode_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Ground-Truthing Mode',...
  'Tag','menu_evaluate_gtmode',...
  'Separator','off',...
  'Checked','off');

handles.menu_evaluate_gtcomputeperf = uimenu('Parent',handles.menu_evaluate,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_evaluate_gtcomputeperf_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Compute GT performance',...
  'Tag','menu_evaluate_gtcomputeperf',...
  'Separator','on');
handles.menu_evaluate_gtcomputeperfimported = uimenu('Parent',handles.menu_evaluate,...
  'Callback',@(hObject,eventdata)LabelerGUI('menu_evaluate_gtcomputeperfimported_Callback',hObject,eventdata,guidata(hObject)),...
  'Label','Compute GT performance (imported predictions)',...
  'Tag','menu_evaluate_gtcomputeperfimported',...
  'Separator','off');

handles.menu_go.Position = 4;
handles.menu_track.Position = 5;
handles.menu_evaluate.Position = 6;
handles.menu_help.Position = 7;

hCMenu = uicontextmenu('parent',handles.figure);
uimenu('Parent',hCMenu,'Label','Freeze to current main window',...
  'Callback',@(src,evt)cbkFreezePrevAxesToMainWindow(src,evt));
uimenu('Parent',hCMenu,'Label','Display last frame seen in main window',...
  'Callback',@(src,evt)cbkUnfreezePrevAxes(src,evt));
handles.axes_prev.UIContextMenu = hCMenu;

% misc labelmode/Setup menu
LABELMODE_SETUPMENU_MAP = ...
  {LabelMode.NONE '';
   LabelMode.SEQUENTIAL 'menu_setup_sequential_mode';
   LabelMode.TEMPLATE 'menu_setup_template_mode';
   LabelMode.HIGHTHROUGHPUT 'menu_setup_highthroughput_mode';
   LabelMode.MULTIVIEWCALIBRATED2 'menu_setup_multiview_calibrated_mode_2'};
tmp = LABELMODE_SETUPMENU_MAP;
tmp(:,1) = cellfun(@char,tmp(:,1),'uni',0);
tmp(2:end,2) = cellfun(@(x)handles.(x),tmp(2:end,2),'uni',0);
tmp = tmp';
handles.labelMode2SetupMenu = struct(tmp{:});
tmp = LABELMODE_SETUPMENU_MAP(2:end,[2 1]);
tmp = tmp';
handles.setupMenu2LabelMode = struct(tmp{:});

hold(handles.axes_occ,'on');
axis(handles.axes_occ,'ij');
set(handles.axes_occ,'XTick',[],'YTick',[]);

handles.image_curr = imagesc(0,'Parent',handles.axes_curr);
set(handles.image_curr,'PickableParts','none');
hold(handles.axes_curr,'on');
set(handles.axes_curr,'Color',[0 0 0]);
handles.image_prev = imagesc(0,'Parent',handles.axes_prev);
set(handles.image_prev,'PickableParts','none');
hold(handles.axes_prev,'on');
set(handles.axes_prev,'Color',[0 0 0]);

handles.figs_all = handles.figure;
handles.axes_all = handles.axes_curr;
handles.images_all = handles.image_curr;

pumTrack = handles.pumTrack;
pumTrack.Value = 1;
pumTrack.String = {'All frames'};
set(pumTrack,'FontUnits','points','FontSize',6.5);
pumTrack.FontUnits = 'normalized';
aptResize = APTResize(handles);
handles.figure.SizeChangedFcn = @(src,evt)aptResize.resize(src,evt);
aptResize.resize(handles.figure,[]);
handles.pumTrack.Callback = ...
  @(hObj,edata)LabelerGUI('pumTrack_Callback',hObj,edata,guidata(hObj));

lObj = handles.labelerObj;

handles.labelTLInfo = InfoTimeline(lObj,handles.axes_timeline_manual);
set(handles.pumInfo,'String',handles.labelTLInfo.getPropsDisp());

listeners = cell(0,1);
listeners{end+1,1} = addlistener(handles.slider_frame,'ContinuousValueChange',@slider_frame_Callback);
listeners{end+1,1} = addlistener(handles.sldZoom,'ContinuousValueChange',@sldZoom_Callback);
listeners{end+1,1} = addlistener(handles.axes_curr,'XLim','PostSet',@(s,e)axescurrXLimChanged(s,e,handles));
listeners{end+1,1} = addlistener(handles.axes_curr,'XDir','PostSet',@(s,e)axescurrXDirChanged(s,e,handles));
listeners{end+1,1} = addlistener(handles.axes_curr,'YDir','PostSet',@(s,e)axescurrYDirChanged(s,e,handles));
listeners{end+1,1} = addlistener(lObj,'projname','PostSet',@cbkProjNameChanged);
listeners{end+1,1} = addlistener(lObj,'currFrame','PostSet',@cbkCurrFrameChanged);
listeners{end+1,1} = addlistener(lObj,'currTarget','PostSet',@cbkCurrTargetChanged);
listeners{end+1,1} = addlistener(lObj,'labeledposNeedsSave','PostSet',@cbkLabeledPosNeedsSaveChanged);
listeners{end+1,1} = addlistener(lObj,'labelMode','PostSet',@cbkLabelModeChanged);
listeners{end+1,1} = addlistener(lObj,'labels2Hide','PostSet',@cbkLabels2HideChanged);
listeners{end+1,1} = addlistener(lObj,'projFSInfo','PostSet',@cbkProjFSInfoChanged);
listeners{end+1,1} = addlistener(lObj,'showTrx','PostSet',@cbkShowTrxChanged);
listeners{end+1,1} = addlistener(lObj,'showTrxCurrTargetOnly','PostSet',@cbkShowTrxCurrTargetOnlyChanged);
listeners{end+1,1} = addlistener(lObj,'tracker','PostSet',@cbkTrackerChanged);
listeners{end+1,1} = addlistener(lObj,'trackModeIdx','PostSet',@cbkTrackModeIdxChanged);
listeners{end+1,1} = addlistener(lObj,'trackNFramesSmall','PostSet',@cbkTrackerNFramesChanged);
listeners{end+1,1} = addlistener(lObj,'trackNFramesLarge','PostSet',@cbkTrackerNFramesChanged);    
listeners{end+1,1} = addlistener(lObj,'trackNFramesNear','PostSet',@cbkTrackerNFramesChanged);
listeners{end+1,1} = addlistener(lObj,'movieCenterOnTarget','PostSet',@cbkMovieCenterOnTargetChanged);
listeners{end+1,1} = addlistener(lObj,'movieRotateTargetUp','PostSet',@cbkMovieRotateTargetUpChanged);
listeners{end+1,1} = addlistener(lObj,'movieForceGrayscale','PostSet',@cbkMovieForceGrayscaleChanged);
listeners{end+1,1} = addlistener(lObj,'movieInvert','PostSet',@cbkMovieInvertChanged);
listeners{end+1,1} = addlistener(lObj,'movieViewBGsubbed','PostSet',@cbkMovieViewBGsubbedChanged);
listeners{end+1,1} = addlistener(lObj,'lblCore','PostSet',@cbkLblCoreChanged);
listeners{end+1,1} = addlistener(lObj,'gtIsGTModeChanged',@cbkGtIsGTModeChanged);
listeners{end+1,1} = addlistener(lObj,'newProject',@cbkNewProject);
listeners{end+1,1} = addlistener(lObj,'newMovie',@cbkNewMovie);
listeners{end+1,1} = addlistener(handles.labelTLInfo,'selectOn','PostSet',@cbklabelTLInfoSelectOn);
listeners{end+1,1} = addlistener(handles.labelTLInfo,'props','PostSet',@cbklabelTLInfoPropsUpdated);
handles.listeners = listeners;

hZ = zoom(hObject);
hZ.ActionPostCallback = @cbkPostZoom;

% These Labeler properties need their callbacks fired to properly init UI.
% Labeler will read .propsNeedInit from the GUIData to comply.
handles.propsNeedInit = {
  'labelMode' 
  'suspScore' 
  'showTrx' 
  'showTrxCurrTargetOnly'
  'tracker' 
  'trackNFramesSmall' % trackNFramesLarge, trackNframesNear currently share same callback
  'trackModeIdx'
  'movieCenterOnTarget'
  'movieForceGrayscale' 
  'movieInvert'};

set(handles.output,'Toolbar','figure');

handles = initTblTrx(handles);
handles = initTblFrames(handles);

figSetPosAPTDefault(hObject);
set(hObject,'Units','normalized');

handles.sldZoom.Min = 0;
handles.sldZoom.Max = 1;
handles.sldZoom.Value = 0;

handles.depHandles = gobjects(0,1);

handles.isPlaying = false;
handles.pbPlay.CData = Icons.ims.play;
handles.pbPlay.BackgroundColor = handles.edit_frame.BackgroundColor;
handles.pbPlaySeg.CData = Icons.ims.playsegment;
handles.pbPlaySeg.BackgroundColor = handles.edit_frame.BackgroundColor;

handles.pbPlaySeg.TooltipString = 'play nearby frames; labels not updated';

guidata(hObject, handles);

% UIWAIT makes LabelerGUI wait for user response (see UIRESUME)
% uiwait(handles.figure);

function handles = initTblTrx(handles)
tbl0 = handles.tblTrx;
COLNAMES = {'Index' 'Labeled'};
jt = uiextras.jTable.Table(...
  'parent',tbl0.Parent,...
  'Position',tbl0.Position,...
  'SelectionMode','discontiguous',...
  'Editable','off',...
  'ColumnPreferredWidth',[100 100],...
  'ColumnName',COLNAMES,... %  'ColumnFormat',{'integer' 'integer' 'integer'},...  'ColumnEditable',[false false false],...
  'CellSelectionCallback',@(src,evt)cbkTblTrxCellSelection(src,evt));
set(jt,'Data',cell(0,numel(COLNAMES)));
cr = aptjava.StripedIntegerTableCellRenderer;
cr.setHorizontalAlignment(javax.swing.JLabel.CENTER);
crCB = aptjava.StripedCheckBoxTableCellRenderer;
jt.JColumnModel.getColumn(0).setCellRenderer(cr);
jt.JColumnModel.getColumn(1).setCellRenderer(crCB);
jt.JTable.Foreground = java.awt.Color.WHITE;
jt.hPanel.BackgroundColor = [0.3 0.3 0.3];
h = jt.JTable.getTableHeader;
h.setPreferredSize(java.awt.Dimension(225,22));
jt.JTable.repaint;

delete(tbl0);
handles.tblTrx = jt;

function handles = initTblFrames(handles)
tbl0 = handles.tblFrames;
COLNAMES = {'Frame' 'Tgts' 'Pts'};
jt = uiextras.jTable.Table(...
  'parent',tbl0.Parent,...
  'Position',tbl0.Position,...
  'SelectionMode','single',...
  'Editable','off',...
  'ColumnPreferredWidth',[100 50],...
  'ColumnName',COLNAMES,... %  'ColumnFormat',{'integer' 'integer' 'integer'},...  'ColumnEditable',[false false false],...
  'CellSelectionCallback',@(src,evt)cbkTblFramesCellSelection(src,evt));
set(jt,'Data',cell(0,numel(COLNAMES)));
cr = aptjava.StripedIntegerTableCellRenderer;
for i=0:2
  jt.JColumnModel.getColumn(i).setCellRenderer(cr);
end
jt.JTable.Foreground = java.awt.Color.WHITE;
jt.hPanel.BackgroundColor = [0.3 0.3 0.3];
h = jt.JTable.getTableHeader;
h.setPreferredSize(java.awt.Dimension(225,22));
jt.JTable.repaint;

delete(tbl0);
handles.tblFrames = jt;

function varargout = LabelerGUI_OutputFcn(hObject, eventdata, handles) %#ok<*INUSL>
varargout{1} = handles.output;

function handles = clearDepHandles(handles)
deleteValidHandles(handles.depHandles);
handles.depHandles = gobjects(0,1);

function handles = addDepHandle(handles,h)
% GC dead handles
tfValid = arrayfun(@isvalid,handles.depHandles);
handles.depHandles = handles.depHandles(tfValid,:);
    
tfSame = arrayfun(@(x)x==h,handles.depHandles);
if ~any(tfSame)
  handles.depHandles(end+1,1) = h;
end

function handles = setShortcuts(handles)

prefs = handles.labelerObj.projPrefs;
if ~isfield(prefs,'Shortcuts')
  return;
end
prefs = prefs.Shortcuts;
fns = fieldnames(prefs);
ismenu = false(1,numel(fns));
for i = 1:numel(fns)
  h = findobj(handles.figure,'Tag',fns{i},'-property','Accelerator');
  if isempty(h) || ~ishandle(h)
    continue;
  end
  ismenu(i) = true;
  set(h,'Accelerator',prefs.(fns{i}));
end

handles.shortcutkeys = cell(1,nnz(~ismenu));
handles.shortcutfns = cell(1,nnz(~ismenu));
idxnotmenu = find(~ismenu);

for ii = 1:numel(idxnotmenu)
  i = idxnotmenu(ii);
  handles.shortcutkeys{ii} = prefs.(fns{i});
  handles.shortcutfns{ii} = fns{i};
end

function cbkAuxAxResize(src,data)
% AL 20160628: voodoo that may help make points more clickable. Sometimes
% pt clickability in MultiViewCalibrated mode is unstable (eg to anchor
% points etc)
ax = findall(src,'type','axes');
axis(ax,'image')
axis(ax,'auto');

function cbkAuxFigCloseReq(src,data,lObj)

handles = lObj.gdata;
if ~any(src==handles.depHandles)
  delete(gcf);
  return;  
end

CLOSESTR = 'Close anyway';
DONTCLOSESTR = 'Cancel, don''t close';
sel = questdlg('This figure is required for your current multiview project.',...
  'Close Request Function',...
  DONTCLOSESTR,CLOSESTR,DONTCLOSESTR);
if isempty(sel)
  sel = DONTCLOSESTR;
end
switch sel
  case DONTCLOSESTR
    % none
  case CLOSESTR
    delete(gcf)
end

function cbkLblCoreChanged(src,evt)
lObj = evt.AffectedObject;
lblCore = lObj.lblCore;
if ~isempty(lblCore)
  lblCore.addlistener('hideLabels','PostSet',@cbkLblCoreHideLabelsChanged);
  cbkLblCoreHideLabelsChanged([],struct('AffectedObject',lblCore));
  if isprop(lblCore,'streamlined')
    lblCore.addlistener('streamlined','PostSet',@cbkLblCoreStreamlinedChanged);
    cbkLblCoreStreamlinedChanged([],struct('AffectedObject',lblCore));
  end
end

function cbkLblCoreHideLabelsChanged(src,evt)
lblCore = evt.AffectedObject;
handles = lblCore.labeler.gdata;
handles.menu_view_hide_labels.Checked = onIff(lblCore.hideLabels);

function cbkLblCoreStreamlinedChanged(src,evt)
lblCore = evt.AffectedObject;
handles = lblCore.labeler.gdata;
handles.menu_setup_streamlined.Checked = onIff(lblCore.streamlined);

function cbkTrackerHideVizChanged(src,evt,hmenu_view_hide_predictions)
tracker = evt.AffectedObject;
hmenu_view_hide_predictions.Checked = onIff(tracker.hideViz);

function cbkKPF(src,evt,lObj)

tfKPused = false;

% first try user-defined KeyPressHandlers
kph = lObj.keyPressHandlers;
for i=1:numel(kph)
  tfKPused = kph(i).handleKeyPress(evt,lObj);
  if tfKPused
    return;
  end
end

tfShift = any(strcmp('shift',evt.Modifier));
tfCtrl = any(strcmp('control',evt.Modifier));

handles = guidata(src);
% KB20160724: shortcuts from preferences
if all(isfield(handles,{'shortcutkeys','shortcutfns'}))
  % control key pressed?
  if tfCtrl && numel(evt.Modifier)==1 && any(strcmpi(evt.Key,handles.shortcutkeys))
    i = find(strcmpi(evt.Key,handles.shortcutkeys),1);
    h = findobj(handles.figure,'Tag',handles.shortcutfns{i},'-property','Callback');
    if isempty(h)
      fprintf('Unknown shortcut handle %s\n',handles.shortcutfns{i});
    else
      cb = get(h,'Callback');
      if isa(cb,'function_handle')
        cb(h,[]);
        tfKPused = true;
      elseif iscell(cb)
        cb{1}(cb{2:end});
        tfKPused = true;
      elseif ischar(cb)
        evalin('base',[cb,';']);
        tfKPused = true;
      end
    end
  end  
end
if tfKPused
  return;
end

lcore = lObj.lblCore;
if ~isempty(lcore)
  tfKPused = lcore.kpf(src,evt);
  if tfKPused
    return;
  end
end

if any(strcmp(evt.Key,{'leftarrow' 'rightarrow'}))
  switch evt.Key
    case 'leftarrow'
      if tfShift
        sam = lObj.movieShiftArrowNavMode;
        [tffound,f] = sam.seekFrame(lObj,-1);
        if tffound
          lObj.setFrameProtected(f);          
        end
      else
        lObj.frameDown(tfCtrl);
      end
    case 'rightarrow'
      if tfShift
        sam = lObj.movieShiftArrowNavMode;
        [tffound,f] = sam.seekFrame(lObj,1);
        if tffound
          lObj.setFrameProtected(f);          
        end
      else
        lObj.frameUp(tfCtrl);
      end
  end
  return;
end

if lObj.gtIsGTMode && strcmp(evt.Key,{'r'})
  lObj.gtNextUnlabeledUI();
  return;
end

% timeline?
      
function cbkWBMF(src,evt,lObj)
lcore = lObj.lblCore;
if ~isempty(lcore)
  lcore.wbmf(src,evt);
end
%lObj.gdata.labelTLInfo.cbkWBMF(src,evt);

function cbkWBUF(src,evt,lObj)
if ~isempty(lObj.lblCore)
  lObj.lblCore.wbuf(src,evt);
end
%lObj.gdata.labelTLInfo.cbkWBUF(src,evt);

function cbkWSWF(src,evt,lObj)
scrollcnt = evt.VerticalScrollCount;
scrollamt = evt.VerticalScrollAmount;
fcurr = lObj.currFrame;
f = fcurr - round(scrollcnt*scrollamt); % scroll "up" => larger frame number
f = min(max(f,1),lObj.nframes);
cmod = lObj.gdata.figure.CurrentModifier;
tfMod = ~isempty(cmod) && any(strcmp(cmod{1},{'control' 'shift'}));
if tfMod
  if f>fcurr
    lObj.frameUp(true);
  else
    lObj.frameDown(true);
  end
else
  lObj.setFrameProtected(f);
end

function cbkNewProject(src,evt)

lObj = src;
handles = lObj.gdata;

handles = clearDepHandles(handles);

% figs, axes, images
deleteValidHandles(handles.figs_all(2:end));
handles.figs_all = handles.figs_all(1);
handles.axes_all = handles.axes_all(1);
handles.images_all = handles.images_all(1);
handles.axes_occ = handles.axes_occ(1);

nview = lObj.nview;
figs = gobjects(1,nview);
axs = gobjects(1,nview);
ims = gobjects(1,nview);
axsOcc = gobjects(1,nview);
figs(1) = handles.figs_all;
axs(1) = handles.axes_all;
ims(1) = handles.images_all;
axsOcc(1) = handles.axes_occ;

% all occluded-axes will have ratios widthAxsOcc:widthAxs and 
% heightAxsOcc:heightAxs equal to that of axsOcc(1):axs(1)
axsOcc1Pos = axsOcc(1).Position;
ax1Pos = axs(1).Position;
axOccSzRatios = axsOcc1Pos(3:4)./ax1Pos(3:4);
axOcc1XColor = axsOcc(1).XColor;

set(ims(1),'CData',0); % reset image
for iView=2:nview
  figs(iView) = figure(...
    'CloseRequestFcn',@(s,e)cbkAuxFigCloseReq(s,e,lObj),...
    'Color',figs(1).Color,...
    'Menubar','none',...
    'Toolbar','figure',...
    'UserData',struct('view',iView)...
    );
  axs(iView) = axes;
  handles = addDepHandle(handles,figs(iView));
  
  ims(iView) = imagesc(0,'Parent',axs(iView));
  set(ims(iView),'PickableParts','none');
  %axisoff(axs(iView));
  hold(axs(iView),'on');
  set(axs(iView),'Color',[0 0 0]);
  
  axparent = axs(iView).Parent;
  axpos = axs(iView).Position;
  axunits = axs(iView).Units;
  axpos(3:4) = axpos(3:4).*axOccSzRatios;
  axsOcc(iView) = axes('Parent',axparent,'Position',axpos,'Units',axunits,...
    'Color',[0 0 0],'Box','on','XTick',[],'YTick',[],'XColor',axOcc1XColor,...
    'YColor',axOcc1XColor);
  hold(axsOcc(iView),'on');
  axis(axsOcc(iView),'ij');
end
handles.figs_all = figs;
handles.axes_all = axs;
handles.images_all = ims;
handles.axes_occ = axsOcc;

if isfield(handles,'allAxHiliteMgr') && ~isempty(handles.allAxHiliteMgr)
  % Explicit deletion not supposed to be nec
  delete(handles.allAxHiliteMgr);
end
handles.allAxHiliteMgr = AxesHighlightManager(axs);

axis(handles.axes_occ,[0 lObj.nLabelPoints+1 0 2]);

% The link destruction/recreation may not be necessary
if isfield(handles,'hLinkPrevCurr') && isvalid(handles.hLinkPrevCurr)
  delete(handles.hLinkPrevCurr);
end
viewCfg = lObj.projPrefs.View;
handles.newProjAxLimsSetInConfig = hlpSetConfigOnViews(viewCfg,handles,...
  viewCfg(1).CenterOnTarget); % lObj.CenterOnTarget is not set yet
AX_LINKPROPS = {'XLim' 'YLim' 'XDir' 'YDir'};
handles.hLinkPrevCurr = ...
  linkprop([handles.axes_curr,handles.axes_prev],AX_LINKPROPS);

arrayfun(@(x)colormap(x,gray),figs);
viewNames = lObj.viewNames;
for i=1:nview
  vname = viewNames{i};
  if isempty(vname)
    figs(i).Name = ''; 
  else
    figs(i).Name = sprintf('View: %s',vname);    
  end
end

% % AL: important to get clickable points. Somehow this jiggers plot
% % lims/scaling/coords so that points are more clickable; otherwise
% % lblCore points in aux axes are impossible to click (eg without zooming
% % way in or other contortions)
% for i=2:numel(figs)
%   figs(i).ResizeFcn = @cbkAuxAxResize;
% end
% for i=1:numel(axs)
%   zoomOutFullView(axs(i),[],true);
% end

arrayfun(@(x)zoom(x,'off'),handles.figs_all); % Cannot set KPF if zoom or pan is on
arrayfun(@(x)pan(x,'off'),handles.figs_all);
hTmp = findall(handles.figs_all,'-property','KeyPressFcn','-not','Tag','edit_frame');
set(hTmp,'KeyPressFcn',@(src,evt)cbkKPF(src,evt,lObj));
set(handles.figs_all,'WindowButtonMotionFcn',@(src,evt)cbkWBMF(src,evt,lObj));
set(handles.figs_all,'WindowButtonUpFcn',@(src,evt)cbkWBUF(src,evt,lObj));
if ispc
  set(handles.figs_all,'WindowScrollWheelFcn',@(src,evt)cbkWSWF(src,evt,lObj));
end

handles = setShortcuts(handles);

handles.labelTLInfo.initNewProject();

if isfield(handles,'movieMgr') && isvalid(handles.movieMgr)
  delete(handles.movieMgr);
end
handles.movieMgr = MovieManagerController(handles.labelerObj);
drawnow; % 20171002 Without this, new tabbed MovieManager shows up with 
  % buttons clipped at bottom edge of UI (manually resizing UI then "snaps"
  % buttons/figure back into a good state)   
handles.movieMgr.setVisible(false);

handles.GTMgr = GTManager(handles.labelerObj);
handles.GTMgr.Visible = 'off';
handles = addDepHandle(handles,handles.GTMgr);

guidata(handles.figure,handles);
  
function cbkNewMovie(src,evt)
lObj = src;
handles = lObj.gdata;
%movRdrs = lObj.movieReader;
%ims = arrayfun(@(x)x.readframe(1),movRdrs,'uni',0);
hAxs = handles.axes_all;
hIms = handles.images_all; % Labeler has already loaded with first frame
assert(isequal(lObj.nview,numel(hAxs),numel(hIms)));

tfResetAxLims = evt.isFirstMovieOfProject || lObj.movieRotateTargetUp;
tfResetAxLims = repmat(tfResetAxLims,lObj.nview,1);
if isfield(handles,'newProjAxLimsSetInConfig')
  % AL20170520 Legacy projects did not save their axis lims in the .lbl
  % file. 
  tfResetAxLims = tfResetAxLims | ~handles.newProjAxLimsSetInConfig;
  handles = rmfield(handles,'newProjAxLimsSetInConfig');
end
tfResetCLims = evt.isFirstMovieOfProject;

% Deal with Axis and Color limits.
for iView = 1:lObj.nview	  
  % AL20170518. Different scenarios leads to different desired behavior
  % here:
  %
  % 1. User created a new project (without specifying axis lims in the cfg)
  % and added the first movie. Here, ViewConfig.setCfgOnViews should have
  % set .X/YLimMode to 'auto', so that the axis would  rescale for the 
  % first frame to be shown. However, given the practical vagaries of 
  % initialization, it is too fragile to rely on this. Instead, in the case 
  % of a first-movie-of-a-proj, we explicitly zoom the axes out to fit the 
  % image.
  %
  % 2. User changed movies in an existing project (no targets).
  % Here, the user has already set axis limits appropriately so we do not
  % want to touch the axis limits.
  %
  % 3. User changed movies in an existing project with targets and 
  % Center/Rotate Movie on Target is on. 
  % Here, the user will probably appreciate a wide/full view before zooming
  % back into a target.
  %
  % 4. User changed movies in an eixsting project, except the new movie has
  % a different size compared to the previous. CURRENTLY THIS IS
  % 'UNSUPPORTED' ie we don't attempt to make this behave nicely. The vast
  % majority of projects will have movies of a given/fixed size.
  
  if tfResetAxLims(iView)
    zoomOutFullView(hAxs(iView),hIms(iView),true);
  end
  if tfResetCLims
    hAxs(iView).CLimMode = 'auto';
  end
end

handles.labelTLInfo.initNewMovie();
handles.labelTLInfo.setLabelsFull();

nframes = lObj.nframes;
sliderstep = [1/(nframes-1),min(1,100/(nframes-1))];
set(handles.slider_frame,'Value',0,'SliderStep',sliderstep);

tfHasMovie = lObj.currMovie>0;
if tfHasMovie
  ifo = lObj.movieInfoAllGTaware{lObj.currMovie,1}.info;
  minzoomrad = 10;
  maxzoomrad = (ifo.nc+ifo.nr)/4;
  handles.sldZoom.UserData = log([minzoomrad maxzoomrad]);
end

TRX_MENUS = {...
  'menu_view_trajectories_centervideoontarget'
  'menu_view_rotate_video_target_up'
  'menu_view_hide_trajectories'
  'menu_view_plot_trajectories_current_target_only'
  'menu_setup_label_overlay_montage_trx_centered'};
onOff = onIff(lObj.hasTrx);
cellfun(@(x)set(handles.(x),'Enable',onOff),TRX_MENUS);
set(handles.tblTrx,'Enabled',onOff);
guidata(handles.figure,handles);

setPUMTrackStrs(lObj);

% See note in AxesHighlightManager: Trx vs noTrx, Axes vs Panels
handles.allAxHiliteMgr.setHilitePnl(lObj.hasTrx);

hlpGTUpdateAxHilite(lObj);

% update HUD, statusbar
mname = lObj.moviename;
if lObj.nview>1
  movstr = 'Movieset';
else
  movstr = 'Movie';
end
if lObj.gtIsGTMode
  str = sprintf('%s %d (GT): %s',movstr,lObj.currMovie,mname);  
else
  str = sprintf('%s %d: %s',movstr,lObj.currMovie,mname);
end
set(handles.txMoviename,'String',str);
if ~isempty(mname)
  str = sprintf('new %s %s at %s',lower(movstr),mname,datestr(now,16));
  set(handles.txStatus,'String',str);
  
  % Fragile behavior when loading projects; want project status update to
  % persist and not movie status update. This depends on detailed ordering in 
  % Labeler.projLoad
end

function zoomOutFullView(hAx,hIm,resetCamUpVec)
if isequal(hIm,[])
  axis(hAx,'auto');
else
  set(hAx,...
    'XLim',[.5,size(hIm.CData,2)+.5],...
    'YLim',[.5,size(hIm.CData,1)+.5]);
end
axis(hAx,'image');
zoom(hAx,'reset');
if resetCamUpVec
  hAx.CameraUpVectorMode = 'auto';
end
hAx.CameraViewAngleMode = 'auto';
hAx.CameraPositionMode = 'auto';
hAx.CameraTargetMode = 'auto';

function cbkCurrFrameChanged(src,evt) %#ok<*INUSD>
lObj = evt.AffectedObject;
frm = lObj.currFrame;
nfrm = lObj.nframes;
handles = lObj.gdata;
set(handles.edit_frame,'String',num2str(frm));
sldval = (frm-1)/(nfrm-1);
if isnan(sldval)
  sldval = 0;
end
set(handles.slider_frame,'Value',sldval);
if ~lObj.isinit
  handles.labelTLInfo.newFrame(frm);
  hlpGTUpdateAxHilite(lObj);
end

function hlpGTUpdateAxHilite(lObj)
if lObj.gtIsGTMode
  tfHilite = lObj.gtCurrMovFrmTgtIsInGTSuggestions();
else
  tfHilite = false;
end
lObj.gdata.allAxHiliteMgr.setHighlight(tfHilite);

function cbkCurrTargetChanged(src,evt) %#ok<*INUSD>
lObj = evt.AffectedObject;
if lObj.hasTrx && ~lObj.isinit
  iTgt = lObj.currTarget;
  lObj.currImHud.updateTarget(iTgt);
  lObj.gdata.labelTLInfo.newTarget();
  hlpGTUpdateAxHilite(lObj);
end

function cbkLabeledPosNeedsSaveChanged(src,evt)
lObj = evt.AffectedObject;
hTx = lObj.gdata.txUnsavedChanges;
val = lObj.labeledposNeedsSave;
if isscalar(val) && val
  set(hTx,'Visible','on');
else
  set(hTx,'Visible','off');
end

function menuSetupLabelModeHelp(handles,labelMode)
% Set .Checked for menu_setup_<variousLabelModes> based on labelMode
menus = fieldnames(handles.setupMenu2LabelMode);
for m = menus(:)',m=m{1}; %#ok<FXSET>
  handles.(m).Checked = 'off';
end
hMenu = handles.labelMode2SetupMenu.(char(labelMode));
hMenu.Checked = 'on';

function cbkLabelModeChanged(src,evt)
lObj = evt.AffectedObject;
handles = lObj.gdata;
lblMode = lObj.labelMode;
menuSetupLabelModeHelp(handles,lblMode);
switch lblMode
  case LabelMode.SEQUENTIAL
%     handles.menu_setup_createtemplate.Visible = 'off';
    handles.menu_setup_set_labeling_point.Visible = 'off';
    handles.menu_setup_set_nframe_skip.Visible = 'off';
    handles.menu_setup_streamlined.Visible = 'off';
    handles.menu_setup_unlock_all_frames.Visible = 'off';
    handles.menu_setup_lock_all_frames.Visible = 'off';
    handles.menu_setup_load_calibration_file.Visible = 'off';
  case LabelMode.TEMPLATE
%     handles.menu_setup_createtemplate.Visible = 'on';
    handles.menu_setup_set_labeling_point.Visible = 'off';
    handles.menu_setup_set_nframe_skip.Visible = 'off';
    handles.menu_setup_streamlined.Visible = 'off';
    handles.menu_setup_unlock_all_frames.Visible = 'off';
    handles.menu_setup_lock_all_frames.Visible = 'off';
    handles.menu_setup_load_calibration_file.Visible = 'off';
  case LabelMode.HIGHTHROUGHPUT
%     handles.menu_setup_createtemplate.Visible = 'off';
    handles.menu_setup_set_labeling_point.Visible = 'on';
    handles.menu_setup_set_nframe_skip.Visible = 'on';
    handles.menu_setup_streamlined.Visible = 'off';
    handles.menu_setup_unlock_all_frames.Visible = 'off';
    handles.menu_setup_lock_all_frames.Visible = 'off';
    handles.menu_setup_load_calibration_file.Visible = 'off';
%   case LabelMode.ERRORCORRECT
%     handles.menu_setup_createtemplate.Visible = 'off';
%     handles.menu_setup_set_labeling_point.Visible = 'off';
%     handles.menu_setup_set_nframe_skip.Visible = 'off';
%     handles.menu_setup_streamlined.Visible = 'off';
%     handles.menu_setup_unlock_all_frames.Visible = 'on';
%     handles.menu_setup_lock_all_frames.Visible = 'on';
%     handles.menu_setup_load_calibration_file.Visible = 'off';
  case {LabelMode.MULTIVIEWCALIBRATED2}
%     handles.menu_setup_createtemplate.Visible = 'off';
    handles.menu_setup_set_labeling_point.Visible = 'off';
    handles.menu_setup_set_nframe_skip.Visible = 'off';
    handles.menu_setup_streamlined.Visible = 'on';
    handles.menu_setup_unlock_all_frames.Visible = 'off';
    handles.menu_setup_lock_all_frames.Visible = 'off';
    handles.menu_setup_load_calibration_file.Visible = 'on';
end

lc = lObj.lblCore;
tfShow3DAxes = ~isempty(lc) && lc.supportsMultiView && lc.supportsCalibration;
% handles.menu_view_show_3D_axes.Enable = onIff(tfShow3DAxes);

function hlpUpdateTxProjectName(lObj)
projname = lObj.projname;
info = lObj.projFSInfo;
if isempty(info)
  str = projname;
else
  [~,projfileS] = myfileparts(info.filename);  
  str = sprintf('%s / %s',projfileS,projname);
end
hTX = lObj.gdata.txProjectName;
hTX.String = str;

function cbkProjNameChanged(src,evt)
lObj = evt.AffectedObject;
handles = lObj.gdata;
pname = lObj.projname;
str = sprintf('Project %s created (unsaved) at %s',pname,datestr(now,16));
set(handles.txStatus,'String',str);
hlpUpdateTxProjectName(lObj);

function cbkProjFSInfoChanged(src,evt)
lObj = evt.AffectedObject;
info = lObj.projFSInfo;
if ~isempty(info)  
  str = sprintf('Project %s %s at %s',info.filename,info.action,datestr(info.timestamp,16));
  set(lObj.gdata.txStatus,'String',str);
end
hlpUpdateTxProjectName(lObj);

function cbkMovieForceGrayscaleChanged(src,evt)
lObj = evt.AffectedObject;
tf = lObj.movieForceGrayscale;
mnu = lObj.gdata.menu_view_converttograyscale;
mnu.Checked = onIff(tf);

function cbkMovieInvertChanged(src,evt)
lObj = evt.AffectedObject;
figs = lObj.gdata.figs_all;
movInvert = lObj.movieInvert;
viewNames = lObj.viewNames;
for i=1:lObj.nview
  name = viewNames{i};
  if isempty(name)
    name = ''; 
  else
    name = sprintf('View: %s',name);
  end
  if movInvert(i)
    name = [name ' (movie inverted)']; %#ok<AGROW>
  end
  figs(i).Name = name;
end

function cbkMovieViewBGsubbedChanged(src,evt)
lObj = evt.AffectedObject;
tf = lObj.movieViewBGsubbed;
mnu = lObj.gdata.menu_view_show_bgsubbed_frames;
mnu.Checked = onIff(tf);

% function cbkSuspScoreChanged(src,evt)
% lObj = evt.AffectedObject;
% ss = lObj.suspScore;
% lObj.currImHud.updateReadoutFields('hasSusp',~isempty(ss));
% 
% assert(~lObj.gtIsGTMode,'Unsupported in GT mode.');
% 
% handles = lObj.gdata;
% pnlSusp = handles.pnlSusp;
% tblSusp = handles.tblSusp;
% tfDoSusp = ~isempty(ss) && lObj.hasMovie && ~lObj.isinit;
% if tfDoSusp 
%   nfrms = lObj.nframes;
%   ntgts = lObj.nTargets;
%   [tgt,frm] = meshgrid(1:ntgts,1:nfrms);
%   ss = ss{lObj.currMovie};
%   
%   frm = frm(:);
%   tgt = tgt(:);
%   ss = ss(:);
%   tfnan = isnan(ss);
%   frm = frm(~tfnan);
%   tgt = tgt(~tfnan);
%   ss = ss(~tfnan);
%   
%   [ss,idx] = sort(ss,1,'descend');
%   frm = frm(idx);
%   tgt = tgt(idx);
%   
%   mat = [frm tgt ss];
%   tblSusp.Data = mat;
%   pnlSusp.Visible = 'on';
%   
%   if verLessThan('matlab','R2015b') % findjobj doesn't work for >=2015b
%     
%     % make tblSusp column-sortable. 
%     % AL 201510: Tried putting this in opening_fcn but
%     % got weird behavior (findjobj couldn't find jsp)
%     jscrollpane = findjobj(tblSusp);
%     jtable = jscrollpane.getViewport.getView;
%     jtable.setSortable(true);		% or: set(jtable,'Sortable','on');
%     jtable.setAutoResort(true);
%     jtable.setMultiColumnSortable(true);
%     jtable.setPreserveSelectionsAfterSorting(true);
%     % reset ColumnWidth, jtable messes it up
%     cwidth = tblSusp.ColumnWidth;
%     cwidth{end} = cwidth{end}-1;
%     tblSusp.ColumnWidth = cwidth;
%     cwidth{end} = cwidth{end}+1;
%     tblSusp.ColumnWidth = cwidth;
%   
%     tblSusp.UserData = struct('jtable',jtable);   
%   else
%     % none
%   end
%   lObj.updateCurrSusp();
% else
%   tblSusp.Data = cell(0,3);
%   pnlSusp.Visible = 'off';
% end

% function cbkCurrSuspChanged(src,evt)
% lObj = evt.AffectedObject;
% ss = lObj.currSusp;
% if ~isequal(ss,[])
%   lObj.currImHud.updateSusp(ss);
% end

function cbkTrackerChanged(src,evt)
lObj = evt.AffectedObject;
tObj = lObj.tracker;
tf = ~isempty(tObj);
onOff = onIff(tf);
handles = lObj.gdata;
handles.menu_track.Enable = onOff;
handles.pbTrain.Enable = onOff;
handles.pbTrack.Enable = onOff;
handles.menu_view_hide_predictions.Enable = onOff;
if tf
  tObj.addlistener('hideViz','PostSet',@(src1,evt1) cbkTrackerHideVizChanged(src1,evt1,handles.menu_view_hide_predictions));
  tObj.addlistener('trnDataDownSamp','PostSet',@(src1,evt1) cbkTrackerTrnDataDownSampChanged(src1,evt1,handles));
  tObj.addlistener('showVizReplicates','PostSet',@(src1,evt1) cbkTrackerShowVizReplicatesChanged(src1,evt1,handles));
  tObj.addlistener('storeFullTracking','PostSet',@(src1,evt1) cbkTrackerStoreFullTrackingChanged(src1,evt1,handles));
end
handles.labelTLInfo.setTracker(tObj);

function cbkTrackModeIdxChanged(src,evt)
lObj = evt.AffectedObject;
if lObj.isinit
  return;
end
hPUM = lObj.gdata.pumTrack;
hPUM.Value = lObj.trackModeIdx;
% Edge case: conceivably, pumTrack.Strings may not be updated (eg for a
% noTrx->hasTrx transition before this callback fires). In this case,
% hPUM.Value (trackModeIdx) will be out of bounds and a warning till be
% thrown, PUM will not be displayed etc. However when hPUM.value is
% updated, this should resolve.

function cbkTrackerNFramesChanged(src,evt)
lObj = evt.AffectedObject;
if lObj.isinit
  return;
end
setPUMTrackStrs(lObj);

function setPUMTrackStrs(lObj)
if lObj.hasTrx
  mfts = MFTSetEnum.TrackingMenuTrx;
else
  mfts = MFTSetEnum.TrackingMenuNoTrx;
end
if ispc || ismac
  menustrs = arrayfun(@(x)x.getPrettyStr(lObj),mfts,'uni',0);
else
  % iss #161
  menustrs = arrayfun(@(x)x.getPrettyStrCompact(lObj),mfts,'uni',0);
end
hPUM = lObj.gdata.pumTrack;
hPUM.String = menustrs;
if lObj.trackModeIdx>numel(menustrs)
  lObj.trackModeIdx = 1;
end

hFig = lObj.gdata.figure;
hFig.SizeChangedFcn(hFig,[]);

function pumTrack_Callback(hObj,edata,handles)
lObj = handles.labelerObj;
lObj.trackModeIdx = hObj.Value;

function mftset = getTrackMode(handles)
idx = handles.pumTrack.Value;
% Note, .TrackingMenuNoTrx==.TrackingMenuTrx(1:K), so we can just index
% .TrackingMenuTrx.
mfts = MFTSetEnum.TrackingMenuTrx;
mftset = mfts(idx);

function cbkMovieCenterOnTargetChanged(src,evt)
lObj = evt.AffectedObject;
tf = lObj.movieCenterOnTarget;
mnu = lObj.gdata.menu_view_trajectories_centervideoontarget;
mnu.Checked = onIff(tf);

function cbkMovieRotateTargetUpChanged(src,evt)
lObj = evt.AffectedObject;
tf = lObj.movieRotateTargetUp;
if tf
  ax = lObj.gdata.axes_curr;
  warnst = warning('off','LabelerGUI:axDir');
  for f={'XDir' 'YDir'},f=f{1}; %#ok<FXSET>
    if strcmp(ax.(f),'reverse')
      warningNoTrace('LabelerGUI:ax','Setting main axis .%s to ''normal''.',f);
      ax.(f) = 'normal';
    end
  end
  warning(warnst);
end
mnu = lObj.gdata.menu_view_rotate_video_target_up;
mnu.Checked = onIff(tf);

function slider_frame_Callback(hObject,~)
% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider

handles = guidata(hObject);
lObj = handles.labelerObj;

if ~lObj.hasProject
  set(hObject,'Value',0);  
  return;
end
if ~lObj.hasMovie
  set(hObject,'Value',0);  
  msgbox('There is no movie open.');
  return;
end

v = get(hObject,'Value');
f = round(1 + v * (lObj.nframes - 1));

cmod = handles.figure.CurrentModifier;
if ~isempty(cmod) && any(strcmp(cmod{1},{'control' 'shift'}))
  if f>lObj.currFrame
    tfSetOccurred = lObj.frameUp(true);
  else
    tfSetOccurred = lObj.frameDown(true);
  end
else
  tfSetOccurred = lObj.setFrameProtected(f);
end
  
if ~tfSetOccurred
  sldval = (lObj.currFrame-1)/(lObj.nframes-1);
  if isnan(sldval)
    sldval = 0;
  end
  set(hObject,'Value',sldval);
end

function slider_frame_CreateFcn(hObject,~,~)
% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end

function edit_frame_Callback(hObject,~,handles)
if ~checkProjAndMovieExist(handles)
  return;
end

lObj = handles.labelerObj;

f = str2double(get(hObject,'String'));
if isnan(f)
  set(hObject,'String',num2str(lObj.currFrame));
  return;
end
f = min(max(1,round(f)),lObj.nframes);
if ~lObj.trxCheckFramesLive(f)
  set(hObject,'String',num2str(lObj.currFrame));
  warnstr = sprintf('Frame %d is out-of-range for current target.',f);
  warndlg(warnstr,'Out of range');
  return;
end
set(hObject,'String',num2str(f));
if f ~= lObj.currFrame
  lObj.setFrame(f)
end 
  
function edit_frame_CreateFcn(hObject,~,~)
if ispc && isequal(get(hObject,'BackgroundColor'), ...
                   get(0,'defaultUicontrolBackgroundColor'))
  set(hObject,'BackgroundColor','white');
end

function pbTrain_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
wbObj = WaitBarWithCancel('Training');
oc = onCleanup(@()delete(wbObj));
centerOnParentFigure(wbObj.hWB,handles.figure);
handles.labelerObj.trackRetrain('wbObj',wbObj);
if wbObj.isCancel
  msg = wbObj.cancelMessage('Training canceled');
  msgbox(msg,'Train');
end
  
function pbTrack_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
tm = getTrackMode(handles);
wbObj = WaitBarWithCancel('Tracking');
centerOnParentFigure(wbObj.hWB,handles.figure);
oc = onCleanup(@()delete(wbObj));
handles.labelerObj.track(tm,'wbObj',wbObj);
if wbObj.isCancel
  msg = wbObj.cancelMessage('Tracking canceled');
  msgbox(msg,'Track');
end

function pbClear_Callback(hObject, eventdata, handles)

if ~checkProjAndMovieExist(handles)
  return;
end
handles.labelerObj.lblCore.clearLabels();

function tbAccept_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
lc = handles.labelerObj.lblCore;
switch lc.state
  case LabelState.ADJUST
    lc.acceptLabels();
  case LabelState.ACCEPTED
    lc.unAcceptLabels();
  otherwise
    assert(false);
end

function cbkTblTrxCellSelection(src,evt) %#ok<*DEFNU>
% Current/last row selection is maintained in hObject.UserData

handles = guidata(src.Parent);
lObj = handles.labelerObj;
if ~lObj.hasTrx
  return;
end

rows = evt.Indices;
rowsprev = src.UserData;
src.UserData = rows;
dat = get(src,'Data');

if isscalar(rows)
  idx = dat{rows(1),1};
  lObj.setTarget(idx);
  lObj.labelsOtherTargetHideAll();
else
  % addon to existing selection
  rowsnew = setdiff(rows,rowsprev);  
  idxsnew = cell2mat(dat(rowsnew,1));
  lObj.labelsOtherTargetShowIdxs(idxsnew);
end

hlpRemoveFocus(src,handles);

function hlpRemoveFocus(h,handles)
% Hack to manage focus. As usual the uitable is causing problems. The
% tables used for Target/Frame nav cause problems with focus/Keypresses as
% follows:
% 1. A row is selected in the target table, selecting that target.
% 2. If nothing else is done, the table has focus and traps arrow
% keypresses to navigate the table, instead of doing LabelCore stuff
% (moving selected points, changing frames, etc).
% 3. The following lines of code force the focus off the uitable.
%
% Other possible solutions: 
% - Figure out how to disable arrow-key nav in uitables. Looks like need to
% drop into Java and not super simple.
% - Don't use uitables, or use them in a separate figure window.
uicontrol(handles.txStatus);

function cbkTblFramesCellSelection(src,evt)
handles = guidata(src.Parent);
lObj = handles.labelerObj;
row = evt.Indices;
if ~isempty(row)
  row = row(1);
  dat = get(src,'Data');
  lObj.setFrame(dat{row,1},'changeTgtsIfNec',true);
end

hlpRemoveFocus(src,handles);

% 20170428
% Notes -- Zooms Views Angles et al
% 
% Zoom.
% In APT we refer to the "zoom" as effective magnification determined by 
% the axis limits, ie how many pixels are shown along x and y. Currently
% the pixels and axis are always square.
% 
% The zoom level can be adjusted in a variety of ways: via the zoom slider,
% the Unzoom button, the manual zoom tools in the toolbar, or 
% View > Zoom out. 
%
% Camroll.
% When Trx are available, the movie can be rotated so that the Trx are
% always at a given orientation (currently, "up"). This is achieved by
% "camrolling" the axes, ie setting axes.CameraUpVector. Currently
% manually camrolling is not available.
%
% CamViewAngle.
% The CameraViewAngle is the AOV of the 'camera' viewing the axes. When
% "camroll" is off (either there are no Trx, or rotateSoTargetIsUp is
% off), axis.CameraViewAngleMode is set to 'auto' and MATLAB selects a
% CameraViewAngle so that the axis fills its outerposition. When camroll is
% on, MATLAB by default chooses a CameraViewAngle that is relatively wide, 
% so that the square axes is very visible as it rotates around. This is a
% bit distracting so currently we choose a smaller CamViewAngle (very 
% arbitrarily). There may be a better way to handle this.

function axescurrXLimChanged(hObject,eventdata,handles)
% log(zoomrad) = logzoomradmax + sldval*(logzoomradmin-logzoomradmax)
ax = eventdata.AffectedObject;
radius = diff(ax.XLim)/2;
hSld = handles.sldZoom;
if ~isempty(hSld.UserData) % empty during init
  userdata = hSld.UserData;
  logzoomradmin = userdata(1);
  logzoomradmax = userdata(2);
  sldval = (log(radius)-logzoomradmax)/(logzoomradmin-logzoomradmax);
  sldval = min(max(sldval,0),1);
  hSld.Value = sldval;
end
function axescurrXDirChanged(hObject,eventdata,handles)
videoRotateTargetUpAxisDirCheckWarn(handles);
function axescurrYDirChanged(hObject,eventdata,handles)
videoRotateTargetUpAxisDirCheckWarn(handles);
function videoRotateTargetUpAxisDirCheckWarn(handles)
ax = handles.axes_curr;
if (strcmp(ax.XDir,'reverse') || strcmp(ax.YDir,'reverse')) && ...
    handles.labelerObj.movieRotateTargetUp
  warningNoTrace('LabelerGUI:axDir',...
    'Main axis ''XDir'' or ''YDir'' is set to ''reverse'' and .movieRotateTargetUp is set. Graphics behavior may be unexpected; proceed at your own risk.');
end

function sldZoom_Callback(hObject, eventdata, ~)
% log(zoomrad) = logzoomradmax + sldval*(logzoomradmin-logzoomradmax)
handles = guidata(hObject);

if ~checkProjAndMovieExist(handles)
  return;
end

lObj = handles.labelerObj;
v = hObject.Value;
userdata = hObject.UserData;
logzoomrad = userdata(2)+v*(userdata(1)-userdata(2));
zoomRad = exp(logzoomrad);
lObj.videoZoom(zoomRad);
hlpRemoveFocus(hObject,handles);

function cbkPostZoom(src,evt)
if verLessThan('matlab','R2016a')
  setappdata(src,'manualZoomOccured',true);
end

function pbResetZoom_Callback(hObject, eventdata, handles)
hAxs = handles.axes_all;
hIms = handles.images_all;
assert(numel(hAxs)==numel(hIms));
arrayfun(@zoomOutFullView,hAxs,hIms,false(1,numel(hIms)));

function pbSetZoom_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.targetZoomRadiusDefault = diff(handles.axes_curr.XLim)/2;

function pbRecallZoom_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.videoCenterOnCurrTarget();
lObj.videoZoom(lObj.targetZoomRadiusDefault);

function tblSusp_CellSelectionCallback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if verLessThan('matlab','R2015b')
  jt = lObj.gdata.tblSusp.UserData.jtable;
  row = jt.getSelectedRow; % 0 based
  frm = jt.getValueAt(row,0);
  iTgt = jt.getValueAt(row,1);
  if ~isempty(frm)
    frm = frm.longValueReal;
    iTgt = iTgt.longValueReal;
    lObj.setFrameAndTarget(frm,iTgt);
    hlpRemoveFocus(hObject,handles);
  end
else
  row = eventdata.Indices(1);
  dat = hObject.Data;
  frm = dat(row,1);
  iTgt = dat(row,2);
  lObj.setFrameAndTarget(frm,iTgt);
  hlpRemoveFocus(hObject,handles);
end

function tbTLSelectMode_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
tl = handles.labelTLInfo;
tl.selectOn = hObject.Value;

function pbClearSelection_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
tl = handles.labelTLInfo;
tl.selectClearSelection();

function cbklabelTLInfoSelectOn(src,evt)
lblTLObj = evt.AffectedObject;
tb = lblTLObj.lObj.gdata.tbTLSelectMode;
tb.Value = lblTLObj.selectOn;

function cbklabelTLInfoPropsUpdated(src,evt)
% Update the props dropdown menu and timeline.
labelTLInfo = evt.AffectedObject;
props = labelTLInfo.getPropsDisp();
set(labelTLInfo.lObj.gdata.pumInfo,'String',props);

function cbkFreezePrevAxesToMainWindow(src,evt)
handles = guidata(src);
handles.labelerObj.setPrevAxesMode(PrevAxesMode.FROZEN);
function cbkUnfreezePrevAxes(src,evt)
handles = guidata(src);
handles.labelerObj.setPrevAxesMode(PrevAxesMode.LASTSEEN);

%% menu
function menu_file_quick_open_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if hlpSave(lObj)
  [tfsucc,movfile,trxfile] = promptGetMovTrxFiles(false);
  if ~tfsucc
    return;
  end
  
  movfile = movfile{1};
  trxfile = trxfile{1};
  
  cfg = Labeler.cfgGetLastProjectConfigNoView;
  if cfg.NumViews>1
    warndlg('Your last project had multiple views. Opening movie with single view.');
    cfg.NumViews = 1;
    cfg.ViewNames = cfg.ViewNames(1);
    cfg.View = cfg.View(1);
  end
  lm = LabelMode.(cfg.LabelMode);
  if lm.multiviewOnly
    cfg.LabelMode = char(LabelMode.TEMPLATE);
  end
  
  lObj.initFromConfig(cfg);
    
  [~,projName,~] = fileparts(movfile);
  lObj.projNew(projName);
  lObj.movieAdd(movfile,trxfile);
  lObj.movieSet(1,'isFirstMovie',true);      
end
function menu_file_new_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if hlpSave(lObj)
  cfg = ProjectSetup(handles.figure);
  if ~isempty(cfg)    
    lObj.initFromConfig(cfg);
    lObj.projNew(cfg.ProjectName);
    handles = lObj.gdata; % initFromConfig, projNew have updated handles
    menu_file_managemovies_Callback([],[],handles);
  end  
end
function menu_file_save_Callback(hObject, eventdata, handles)
handles.labelerObj.projSaveSmart();
handles.labelerObj.projAssignProjNameFromProjFileIfAppropriate();
function menu_file_saveas_Callback(hObject, eventdata, handles)
handles.labelerObj.projSaveAs();
handles.labelerObj.projAssignProjNameFromProjFileIfAppropriate();
function menu_file_load_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if hlpSave(lObj)
  currMovInfo = lObj.projLoad();
  if ~isempty(currMovInfo)
    handles = lObj.gdata; % projLoad updated stuff
    handles.movieMgr.setVisible(true);
    wstr = sprintf('Could not find file for movie(set) %d: %s.\n\nProject opened with no movie selected. Double-click a row in the MovieManager or use the ''Switch to Movie'' button to start working on a movie.',...
      currMovInfo.iMov,currMovInfo.badfile);
    warndlg(wstr,'Movie not found','modal');
  end
end

function tfcontinue = hlpSave(labelerObj)
tfcontinue = true;
OPTION_SAVE = 'Save labels first';
OPTION_PROC = 'Proceed without saving';
OPTION_CANC = 'Cancel';
if labelerObj.labeledposNeedsSave
  res = questdlg('You have unsaved changes to your labels. If you proceed without saving, your changes will be lost.',...
    'Unsaved changes',OPTION_SAVE,OPTION_PROC,OPTION_CANC,OPTION_SAVE);
  switch res
    case OPTION_SAVE
      labelerObj.projSaveSmart();
      labelerObj.projAssignProjNameFromProjFileIfAppropriate();
    case OPTION_CANC
      tfcontinue = false;
    case OPTION_PROC
      % none
  end
end

function menu_file_managemovies_Callback(~,~,handles)
if isfield(handles,'movieMgr')
  handles.movieMgr.setVisible(true);
else
  error('LabelerGUI:movieMgr','Please create or load a project.');
end

function menu_file_import_labels_trk_curr_mov_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if ~lObj.hasMovie
  error('LabelerGUI:noMovie','No movie is loaded.');
end
lObj.gtThrowErrIfInGTMode();
iMov = lObj.currMovie;
haslbls1 = lObj.labelPosMovieHasLabels(iMov); % TODO: method should be unnec
haslbls2 = lObj.movieFilesAllHaveLbls(iMov);
assert(haslbls1==haslbls2);
if haslbls1
  resp = questdlg('Current movie has labels that will be overwritten. OK?',...
    'Import Labels','OK, Proceed','Cancel','Cancel');
  if isempty(resp)
    resp = 'Cancel';
  end
  switch resp
    case 'OK, Proceed'
      % none
    case 'Cancel'
      return;
    otherwise
      assert(false); 
  end
end
handles.labelerObj.labelImportTrkPrompt(iMov);

function menu_file_import_labels2_trk_curr_mov_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
if ~lObj.hasMovie
  error('LabelerGUI:noMovie','No movie is loaded.');
end
iMov = lObj.currMovie; % gt-aware
lObj.labels2ImportTrkPrompt(iMov);

function menu_file_export_labels_trks_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
[tfok,rawtrkname] = lObj.getExportTrkRawnameUI('labels',true);
if ~tfok
  return;
end
lObj.labelExportTrk(1:lObj.nmoviesGTaware,'rawtrkname',rawtrkname);

function menu_file_export_labels_table_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
fname = lObj.getDefaultFilenameExportLabelTable();
[f,p] = uiputfile(fname,'Export File');
if isequal(f,0)
  return;
end
fname = fullfile(p,f);  
VARNAME = 'tblLbls';
s = struct();
s.(VARNAME) = lObj.labelGetMFTableLabeled('useMovNames',true); %#ok<STRNU>
save(fname,'-mat','-struct','s');
fprintf('Saved table ''%s'' to file ''%s''.\n',VARNAME,fname);

function menu_help_Callback(hObject, eventdata, handles)

function menu_help_labeling_actions_Callback(hObject, eventdata, handles)
lblCore = handles.labelerObj.lblCore;
if isempty(lblCore)
  h = 'Please open a movie first.';
else
  h = lblCore.getLabelingHelp();
end
msgbox(h,'Labeling Actions','help');

function menu_help_about_Callback(hObject, eventdata, handles)
str = {'APT: Branson Lab Animal Part Tracker'};
msgbox(str,'About');

function menu_setup_sequential_mode_Callback(hObject,eventdata,handles)
menuSetupLabelModeCbkGeneric(hObject,handles);
function menu_setup_template_mode_Callback(hObject,eventdata,handles)
menuSetupLabelModeCbkGeneric(hObject,handles);
function menu_setup_highthroughput_mode_Callback(hObject,eventdata,handles)
menuSetupLabelModeCbkGeneric(hObject,handles);
function menu_setup_multiview_calibrated_mode_2_Callback(hObject,eventdata,handles)
menuSetupLabelModeCbkGeneric(hObject,handles);
function menuSetupLabelModeCbkGeneric(hObject,handles)
lblMode = handles.setupMenu2LabelMode.(hObject.Tag);
handles.labelerObj.labelingInit('labelMode',lblMode);

function menu_setup_label_overlay_montage_Callback(hObject,evtdata,handles)
handles.labelerObj.labelOverlayMontage('trxCtred',false); 
function menu_setup_label_overlay_montage_trx_centered_Callback(hObject,evtdata,handles)
lObj = handles.labelerObj;
hFig(1) = lObj.labelOverlayMontage('trxCtred',true,...
  'trxCtredRotAlignMeth','none'); 
try
  hFig(2) = lObj.labelOverlayMontage('trxCtred',true,...
    'trxCtredRotAlignMeth','headtail','hFig0',hFig(1)); 
catch ME
  warningNoTrace('Could not create head-tail aligned montage: %s',ME.message);
  hFig(2) = figurecascaded(hFig(1));
end
hFig(3) = lObj.labelOverlayMontage('trxCtred',true,...
  'trxCtredRotAlignMeth','trxtheta','hFig0',hFig(2)); %#ok<NASGU>

function menu_setup_set_nframe_skip_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lc = lObj.lblCore;
assert(isa(lc,'LabelCoreHT'));
nfs = lc.nFrameSkip;
ret = inputdlg('Select labeling frame increment','Set increment',1,{num2str(nfs)});
if isempty(ret)
  return;
end
val = str2double(ret{1});
lc.nFrameSkip = val;
lObj.labelPointsPlotInfo.HighThroughputMode.NFrameSkip = val;
% This state is duped between labelCore and lppi b/c the lifetimes are
% different. LabelCore exists only between movies etc, and is initted from
% lppi. Hmm

function menu_setup_streamlined_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lc = lObj.lblCore;
assert(isa(lc,'LabelCoreMultiViewCalibrated2'));
lc.streamlined = ~lc.streamlined;

function menu_setup_set_labeling_point_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
ipt = lObj.lblCore.iPoint;
ret = inputdlg('Select labeling point','Point number',1,{num2str(ipt)});
if isempty(ret)
  return;
end
ret = str2double(ret{1});
lObj.lblCore.setIPoint(ret);
function menu_setup_load_calibration_file_Callback(hObject, eventdata, handles)
lastCalFile = RC.getprop('lastCalibrationFile');
if isempty(lastCalFile)
  lastCalFile = pwd;
end
[fname,pth] = uigetfile('*.mat','Load Calibration File',lastCalFile);
if isequal(fname,0)
  return;
end
fname = fullfile(pth,fname);

[crObj,tfSetViewSizes] = CalRig.loadCreateCalRigObjFromFile(fname);

lObj = handles.labelerObj;
vcdPW = lObj.viewCalProjWide;
if isempty(vcdPW)
  resp = questdlg('Should calibration apply to i) all movies in project or ii) current movie only?',...
    'Calibration load',...
    'All movies in project',...
    'Current movie only',...
    'Cancel',...
    'All movies in project');
  if isempty(resp)
    resp = 'Cancel';
  end
  switch resp
    case 'All movies in project'
      tfProjWide = true;      
    case 'Current movie only'
      tfProjWide = false;      
    otherwise
      return;
  end
else
  tfProjWide = vcdPW;
end

% Currently there is no UI for altering lObj.viewCalProjWide once it is set

if tfProjWide
  lObj.viewCalSetProjWide(crObj,'tfSetViewSizes',tfSetViewSizes);
else
  lObj.viewCalSetCurrMovie(crObj,'tfSetViewSizes',tfSetViewSizes);
end

RC.saveprop('lastCalibrationFile',fname);

function menu_setup_unlock_all_frames_Callback(hObject, eventdata, handles)
handles.labelerObj.labelPosSetAllMarked(false);
function menu_setup_lock_all_frames_Callback(hObject, eventdata, handles)
handles.labelerObj.labelPosSetAllMarked(true);

function CloseImContrast(lObj,iAxRead,iAxApply)
% ReadClim from axRead and apply to axApply

axAll = lObj.gdata.axes_all;
axRead = axAll(iAxRead);
axApply = axAll(iAxApply);
tfApplyAxPrev = any(iAxApply==1); % axes_prev mirrors axes_curr

clim = get(axRead,'CLim');
if isempty(clim)
	% none; can occur when Labeler is closed
else
	warnst = warning('off','MATLAB:graphicsversion:GraphicsVersionRemoval');
	set(axApply,'CLim',clim);
	warning(warnst);
	if tfApplyAxPrev
		set(lObj.gdata.axes_prev,'CLim',clim);
	end
end		

function [tfproceed,iAxRead,iAxApply] = hlpAxesAdjustPrompt(handles)
lObj = handles.labelerObj;
if ~lObj.isMultiView
	tfproceed = 1;
	iAxRead = 1;
	iAxApply = 1;
else
  fignames = {handles.figs_all.Name}';
  for iFig = 1:numel(fignames)
    if isempty(fignames{iFig})
      fignames{iFig} = sprintf('<unnamed view %d>',iFig);
    end
  end
  opts = [{'All views together'}; fignames];
  [sel,tfproceed] = listdlg(...
    'PromptString','Select view(s) to adjust',...
    'ListString',opts,...
    'SelectionMode','single');
  if tfproceed
    switch sel
      case 1
        iAxRead = 1;
        iAxApply = 1:numel(handles.axes_all);
      otherwise
        iAxRead = sel-1;
        iAxApply = sel-1;
    end
  else
    iAxRead = nan;
    iAxApply = nan;
  end
end

function menu_view_show_bgsubbed_frames_Callback(hObject,evtdata,handles)
tf = ~strcmp(hObject.Checked,'on');
lObj = handles.labelerObj;
lObj.movieViewBGsubbed = tf;

function menu_view_adjustbrightness_Callback(hObject, eventdata, handles)
[tfproceed,iAxRead,iAxApply] = hlpAxesAdjustPrompt(handles);
if tfproceed
  try
  	hConstrast = imcontrast_kb(handles.axes_all(iAxRead));
  catch ME
    switch ME.identifier
      case 'images:imcontrast:unsupportedImageType'
        error(ME.identifier,'%s %s',ME.message,'Try View > Convert to grayscale.');
      otherwise
        ME.rethrow();
    end
  end
	addlistener(hConstrast,'ObjectBeingDestroyed',...
		@(s,e) CloseImContrast(handles.labelerObj,iAxRead,iAxApply));
end
  
function menu_view_converttograyscale_Callback(hObject, eventdata, handles)
tf = ~strcmp(hObject.Checked,'on');
lObj = handles.labelerObj;
lObj.movieForceGrayscale = tf;
if lObj.hasMovie
  % Pure convenience: update image for user rather than wait for next 
  % frame-switch. Could also put this in Labeler.set.movieForceGrayscale.
  lObj.setFrame(lObj.currFrame,'tfforcereadmovie',true);
end
function menu_view_gammacorrect_Callback(hObject, eventdata, handles)
[tfok,~,iAxApply] = hlpAxesAdjustPrompt(handles);
if ~tfok
	return;
end
val = inputdlg('Gamma value:','Gamma correction');
if isempty(val)
  return;
end
gamma = str2double(val{1});
ViewConfig.applyGammaCorrection(handles.images_all,handles.axes_all,...
  handles.axes_prev,iAxApply,gamma);
		
function menu_file_quit_Callback(hObject, eventdata, handles)
CloseGUI(handles);

function cbkShowTrxChanged(src,evt)
lObj = evt.AffectedObject;
handles = lObj.gdata;
onOff = onIff(~lObj.showTrx);
handles.menu_view_hide_trajectories.Checked = onOff;
function cbkShowTrxCurrTargetOnlyChanged(src,evt)
lObj = evt.AffectedObject;
handles = lObj.gdata;
onOff = onIff(lObj.showTrxCurrTargetOnly);
handles.menu_view_plot_trajectories_current_target_only.Checked = onOff;
function menu_view_hide_trajectories_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.setShowTrx(~lObj.showTrx);
function menu_view_plot_trajectories_current_target_only_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.setShowTrxCurrTargetOnly(~lObj.showTrxCurrTargetOnly);

function menu_view_trajectories_centervideoontarget_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.movieCenterOnTarget = ~lObj.movieCenterOnTarget;
function menu_view_rotate_video_target_up_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.movieRotateTargetUp = ~lObj.movieRotateTargetUp;
function menu_view_flip_flipud_movie_only_Callback(hObject, eventdata, handles)
[tfproceed,~,iAxApply] = hlpAxesAdjustPrompt(handles);
if tfproceed
  lObj = handles.labelerObj;
  lObj.movieInvert(iAxApply) = ~lObj.movieInvert(iAxApply);
  if lObj.hasMovie
    lObj.setFrame(lObj.currFrame,'tfforcereadmovie',true);
  end
end
function menu_view_flip_flipud_Callback(hObject, eventdata, handles)
[tfproceed,~,iAxApply] = hlpAxesAdjustPrompt(handles);
if tfproceed
  for iAx = iAxApply(:)'
    ax = handles.axes_all(iAx);
    ax.YDir = toggleAxisDir(ax.YDir);
  end
end
function menu_view_flip_fliplr_Callback(hObject, eventdata, handles)
[tfproceed,~,iAxApply] = hlpAxesAdjustPrompt(handles);
if tfproceed
  for iAx = iAxApply(:)'
    ax = handles.axes_all(iAx);
    ax.XDir = toggleAxisDir(ax.XDir);
%     if ax==handles.axes_curr
%       ax2 = handles.axes_prev;
%       ax2.XDir = toggleAxisDir(ax2.XDir);
%     end
  end
end
function menu_view_fit_entire_image_Callback(hObject, eventdata, handles)
hAxs = handles.axes_all;
hIms = handles.images_all;
assert(numel(hAxs)==numel(hIms));
arrayfun(@zoomOutFullView,hAxs,hIms,true(1,numel(hAxs)));

function menu_view_reset_views_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
viewCfg = lObj.projPrefs.View;
hlpSetConfigOnViews(viewCfg,handles,lObj.movieCenterOnTarget);
movInvert = ViewConfig.getMovieInvert(viewCfg);
lObj.movieInvert = movInvert;
lObj.movieCenterOnTarget = viewCfg(1).CenterOnTarget;
lObj.movieRotateTargetUp = viewCfg(1).RotateTargetUp;

function tfAxLimsSpecifiedInCfg = hlpSetConfigOnViews(viewCfg,handles,centerOnTarget)
axs = handles.axes_all;
tfAxLimsSpecifiedInCfg = ViewConfig.setCfgOnViews(viewCfg,handles.figs_all,axs,...
  handles.images_all,handles.axes_prev);
if ~centerOnTarget
  [axs.CameraUpVectorMode] = deal('auto');
  [axs.CameraViewAngleMode] = deal('auto');
  [axs.CameraTargetMode] = deal('auto');
  [axs.CameraPositionMode] = deal('auto');
end
[axs.DataAspectRatio] = deal([1 1 1]);
handles.menu_view_show_tick_labels.Checked = onIff(~isempty(axs(1).XTickLabel));
handles.menu_view_show_grid.Checked = axs(1).XGrid;

function menu_view_hide_labels_Callback(hObject, eventdata, handles)
lblCore = handles.labelerObj.lblCore;
if ~isempty(lblCore)
  lblCore.labelsHideToggle();
end

function menu_view_hide_predictions_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
tracker = lObj.tracker;
if ~isempty(tracker)
  tracker.hideVizToggle();
end

function menu_view_hide_imported_predictions_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.labels2VizToggle();

function cbkTrackerShowVizReplicatesChanged(hObject, eventdata, handles)
handles.menu_view_show_replicates.Checked = ...
  onIff(handles.labelerObj.tracker.showVizReplicates);

function menu_view_show_replicates_Callback(hObject, eventdata, handles)
tObj = handles.labelerObj.tracker;
vsr = tObj.showVizReplicates;
vsrnew = ~vsr;
sft = tObj.storeFullTracking;
if vsrnew && sft==StoreFullTrackingType.NONE
  warningNoTrace('Tracker will store replicates for final CPR iterations.');
  tObj.storeFullTracking = StoreFullTrackingType.FINALITER;
end
tObj.showVizReplicates = vsrnew;

function cbkLabels2HideChanged(src,evt)
lObj = evt.AffectedObject;
if isempty(lObj.tracker)
  handles = lObj.gdata;
  handles.menu_view_hide_predictions.Checked = onIff(lObj.labels2Hide);
end

function menu_view_show_tick_labels_Callback(hObject, eventdata, handles)
% just use checked state of menu for now, no other state
toggleOnOff(hObject,'Checked');
hlpTickGrid(handles);
function menu_view_show_grid_Callback(hObject, eventdata, handles)
% just use checked state of menu for now, no other state
toggleOnOff(hObject,'Checked');
hlpTickGrid(handles);
function hlpTickGrid(handles)
tfTickOn = strcmp(handles.menu_view_show_tick_labels.Checked,'on');
tfGridOn = strcmp(handles.menu_view_show_grid.Checked,'on');

if tfTickOn || tfGridOn
  set(handles.axes_all,'XTickMode','auto','YTickMode','auto');
else
  set(handles.axes_all,'XTick',[],'YTick',[]);
end
if tfTickOn
  set(handles.axes_all,'XTickLabelMode','auto','YTickLabelMode','auto');
else
  set(handles.axes_all,'XTickLabel',[],'YTickLabel',[]);
end
if tfGridOn
  arrayfun(@(x)grid(x,'on'),handles.axes_all);
else
  arrayfun(@(x)grid(x,'off'),handles.axes_all);
end

% AL20180205 LEAVE ME good functionality just currently dormant. CalRigs
% need to be updated, /reconstruct2d()
%
% function menu_view_show_3D_axes_Callback(hObject,eventdata,handles)
% if isfield(handles,'hShow3D')
%   deleteValidHandles(handles.hShow3D);
% end
% handles.hShow3D = gobjects(0,1);
% 
% tfHide = strcmp(hObject.Checked,'on');
% 
% if tfHide
%   hObject.Checked = 'off';
% else
%   lObj = handles.labelerObj;
%   lc = lObj.lblCore;
%   if ~( ~isempty(lc) && lc.supportsMultiView && lc.supportsCalibration )
%     error('LabelerGUI:multiView',...
%       'Labeling mode must support multiple, calibrated views.');
%   end
%   vcd = lObj.viewCalibrationDataCurrent;
%   if isempty(vcd)
%     error('LabelerGUI:vcd','No view calibration data set.');
%   end
%   % Hmm, is this weird, getting the vcd off Labeler not LabelCore. They
%   % should match however
%   assert(isa(vcd,'CalRig'));
%   crig = vcd;
% 
%   nview = lObj.nview;
%   for iview=1:nview
%     ax = handles.axes_all(iview);
% 
%     VIEWDISTFRAC = 5;
% 
%     % Start from where we want the 3D axes to be located in the view
%     xl = ax.XLim;
%     yl = ax.YLim;
%     x0 = diff(xl)/VIEWDISTFRAC+xl(1);
%     y0 = diff(yl)/VIEWDISTFRAC+yl(1);
% 
%     % Project out into 3D; pick a pt
%     [u_p,v_p,w_p] = crig.reconstruct2d(x0,y0,iview);
%     RECON_T = 5; % don't know units here
%     u0 = u_p(1)+RECON_T*u_p(2);
%     v0 = v_p(1)+RECON_T*v_p(2);
%     w0 = w_p(1)+RECON_T*w_p(2);
% 
%     % Loop and find the scale where the the maximum projected length is ~
%     % 1/8th the current view
%     SCALEMIN = 0;
%     SCALEMAX = 20;
%     SCALEN = 300;
%     avViewSz = (diff(xl)+diff(yl))/2;
%     tgtDX = avViewSz/VIEWDISTFRAC*.8;  
%     scales = linspace(SCALEMIN,SCALEMAX,SCALEN);
%     for iScale = 1:SCALEN
%       % origin is (u0,v0,w0) in 3D; (x0,y0) in 2D
% 
%       s = scales(iScale);    
%       [x1,y1] = crig.project3d(u0+s,v0,w0,iview);
%       [x2,y2] = crig.project3d(u0,v0+s,w0,iview);
%       [x3,y3] = crig.project3d(u0,v0,w0+s,iview);
%       d1 = sqrt( (x1-x0).^2 + (y1-y0).^2 );
%       d2 = sqrt( (x2-x0).^2 + (y2-y0).^2 );
%       d3 = sqrt( (x3-x0).^2 + (y3-y0).^2 );
%       if d1>tgtDX || d2>tgtDX || d3>tgtDX
%         fprintf(1,'Found scale for t=%.2f: %.2f\n',RECON_T,s);
%         break;
%       end
%     end
% 
%     LINEWIDTH = 2;
%     FONTSIZE = 12;
%     handles.hShow3D(end+1,1) = plot(ax,[x0 x1],[y0 y1],'r-','LineWidth',LINEWIDTH);
%     handles.hShow3D(end+1,1) = text(x1,y1,'x','Color',[1 0 0],...
%       'fontweight','bold','fontsize',FONTSIZE,'parent',ax);
%     handles.hShow3D(end+1,1) = plot(ax,[x0 x2],[y0 y2],'g-','LineWidth',LINEWIDTH);
%     handles.hShow3D(end+1,1) = text(x2,y2,'y','Color',[0 1 0],...
%       'fontweight','bold','fontsize',FONTSIZE,'parent',ax);
%     handles.hShow3D(end+1,1) = plot(ax,[x0 x3],[y0 y3],'y-','LineWidth',LINEWIDTH);
%     handles.hShow3D(end+1,1) = text(x3,y3,'z','Color',[1 1 0],...
%       'fontweight','bold','fontsize',FONTSIZE,'parent',ax);
%   end
%   hObject.Checked = 'on';
% end
% guidata(hObject,handles);

function menu_track_setparametersfile_Callback(hObject, eventdata, handles)
% Really, "configure parameters"

lObj = handles.labelerObj;
tObj = lObj.tracker;
assert(~isempty(tObj));
%assert(isa(tObj,'CPRLabelTracker'));

% Find either the current parameters or some other starting pt
sPrmOld = lObj.trackGetParams();
if isempty(sPrmOld) || ~isfield(sPrmOld,'Model') % eg new tracker
  sPrmNewOverlay = RC.getprop('lastCPRAPTParams'); % new-style params
  if isempty(sPrmNewOverlay)
    % sPrmNewOverlay could be [] if prop hasn't been set
    sPrmNewOverlay = struct();
    sPrmNewOverlay.ROOT.Track.NFramesSmall = lObj.trackNFramesSmall;
    sPrmNewOverlay.ROOT.Track.NFramesLarge = lObj.trackNFramesLarge;
    sPrmNewOverlay.ROOT.Track.NFramesNeighborhood = lObj.trackNFramesNear;
  else
    % 20180310: sPrmNewOverlay could be in an older format, and it came up
    % in testing. Perform contortions    
    sPrmNewOverlay = ...
      CPRParam.new2old(sPrmNewOverlay,lObj.nPhysPoints,lObj.nview); % don't worry about trackNFramesSmall, etc
    preProcTmp = sPrmNewOverlay.PreProc; % save this, b/c next line
    sPrmNewOverlay = CPRLabelTracker.modernizeParams(sPrmNewOverlay); % removes .PreProc
    sPrmNewOverlay.PreProc = preProcTmp; % yes, .PreProc should get modernized too, but this is not currently factored in Labeler.m
    sPrmNewOverlay = CPRParam.old2new(sPrmNewOverlay,lObj);
    
    % 20180310: Note, these contortions are not totally critical, b/c we 
    % are just creating the starting point for user review. They still need 
    % to actively "Accept" for anything to be set.
  end
  
else
  sPrmNewOverlay = CPRParam.old2new(sPrmOld,lObj);
end

% Start with default "new" parameter tree/specification
prmBaseYaml = CPRLabelTracker.DEFAULT_PARAMETER_FILE;
tPrm = parseConfigYaml(prmBaseYaml);
% Overlay our starting pt
tPrm.structapply(sPrmNewOverlay);
sPrm = ParameterSetup(handles.figure,tPrm,'labelerObj',lObj); % modal

if isempty(sPrm)
  % user canceled; none
else
  RC.saveprop('lastCPRAPTParams',sPrm);
  [sPrm,lObj.trackNFramesSmall,lObj.trackNFramesLarge,...
    lObj.trackNFramesNear] = CPRParam.new2old(sPrm,lObj.nPhysPoints,lObj.nview);
  lObj.trackSetParams(sPrm);
end

function cbkTrackerTrnDataDownSampChanged(src,evt,handles)
tracker = evt.AffectedObject;
if tracker.trnDataDownSamp
  handles.menu_track_use_all_labels_to_train.Checked = 'off';
  handles.menu_track_select_training_data.Checked = 'on';
else
  handles.menu_track_use_all_labels_to_train.Checked = 'on';
  handles.menu_track_select_training_data.Checked = 'off';
end

function menu_track_use_all_labels_to_train_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
tObj = lObj.tracker;
if isempty(tObj)
  error('LabelerGUI:tracker','No tracker for this project.');
end
if tObj.hasTrained && tObj.trnDataDownSamp
  resp = questdlg('A tracker has already been trained with downsampled training data. Proceeding will clear all previous trained/tracked results. OK?',...
    'Clear Existing Tracker','Yes, clear previous tracker','Cancel','Cancel');
  if isempty(resp)
    resp = 'Cancel';
  end
  switch resp
    case 'Yes, clear previous tracker'
      % none
    case 'Cancel'
      return;
  end
end
tObj.trnDataUseAll();

% function menu_track_select_training_data_Callback(hObject, eventdata, handles)
% tObj = handles.labelerObj.tracker;
% if tObj.hasTrained
%   resp = questdlg('A tracker has already been trained. Downsampling training data will clear all previous trained/tracked results. Proceed?',...
%     'Clear Existing Tracker','Yes, clear previous tracker','Cancel','Cancel');
%   if isempty(resp)
%     resp = 'Cancel';
%   end
%   switch resp
%     case 'Yes, clear previous tracker'
%       % none
%     case 'Cancel'
%       return;
%   end
% end
% tObj.trnDataSelect();

function menu_track_training_data_montage_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
lObj.tracker.trainingDataMontage();

function menu_track_trainincremental_Callback(hObject, eventdata, handles)
handles.labelerObj.trackTrain();

function menu_go_targets_summary_Callback(hObject, eventdata, handles)
handles.labelerObj.targetsTableUI();

function menu_go_nav_prefs_Callback(hObject, eventdata, handles)
handles.labelerObj.navPrefsUI();

function menu_evaluate_crossvalidate_Callback(hObject, eventdata, handles)

lObj = handles.labelerObj;
if lObj.tracker.hasTrained
  resp = questdlg('Any existing trained tracker and tracking results will be cleared. Proceed?',...
    'Cross Validation',...
    'OK, Proceed','Cancel','Cancel');
  if isempty(resp)
    resp = 'Cancel';
  end
  switch resp
    case 'OK, Proceed'
      % none
    case 'Cancel'
      return;
    otherwise
      assert(false);
  end
end

tblMFgt = lObj.preProcGetMFTableLbled();
inputstr = sprintf('This project has %d labeled frames.\nNumber of folds for k-fold cross validation:',...
  height(tblMFgt));
resp = inputdlg(inputstr,'Cross Validation',1,{'7'});
if isempty(resp)
  return;
end
nfold = str2double(resp{1});
if round(nfold)~=nfold || nfold<=1
  error('LabelerGUI:xvalid','Number of folds must be a positive integer greater than 1.');
end
      
wbObj = WaitBarWithCancel('Cross Validation');
oc = onCleanup(@()delete(wbObj));
lObj.trackCrossValidate('kfold',nfold,'wbObj',wbObj,'tblMFgt',tblMFgt);
if wbObj.isCancel
  msg = wbObj.cancelMessage('Cross validation canceled');
  msgbox(msg,'Cross Validation');
  return;
end

tblXVres = lObj.xvResults;
nGT = height(tblXVres);
nFold = max(tblXVres.fold);
muErrPt = nanmean(tblXVres.dGTTrk,1); % [1xnpt]
muErr = nanmean(muErrPt); % each pt equal wt
fcnMuErr = @(zErr)nanmean(zErr(:));
tblErrMov = rowfun(fcnMuErr,tblXVres,'GroupingVariables','mov',...
  'InputVariables',{'dGTTrk'},'OutputVariableNames',{'err'});
tblfldsassert(tblErrMov,{'mov' 'GroupCount','err'});
tblErrMov.Properties.VariableNames{2} = 'count';

PTILES = [50 75 90 95];
errptls = prctile(tblXVres.dGTTrk(:),PTILES);
errptls = num2cell(errptls);
errptlsstr = sprintf('%.1f, ',errptls{:});
errptlsstr = errptlsstr(1:end-2);

str = { ...
  sprintf('GT dataset: %d labeled frames across %d movies',nGT,...
    height(tblErrMov));
  sprintf('Number of cross-validation folds: %d',nFold);
  '';
  sprintf('Mean err, all points (px): %.2f',muErr);
  };
  
for imov=1:height(tblErrMov)
  trow = tblErrMov(imov,:);
  %   [path,movS] = myfileparts(trow.mov{1});
  %   [~,path] = myfileparts(path);
  %   mov = fullfile(path,movS);
  str{end+1,1} = sprintf(' ... movie %d (%d rows): %.2f',double(trow.mov),...
    trow.count,trow.err); %#ok<AGROW>
end

str{end+1,1} = '';
str{end+1,1} = sprintf('Error, %sth percentiles (px):',mat2str(PTILES));

errptlspts = prctile(tblXVres.dGTTrk,PTILES)'; % [nLabelPoints x nptiles]
npts = size(errptlspts,1);
for ipt=1:npts
  errptlsI = errptlspts(ipt,:);
  errptlsI = num2cell(errptlsI);
  errptlsIstr = sprintf('%.1f, ',errptlsI{:});
  errptlsIstr = errptlsIstr(1:end-2);
  str{end+1,1} = sprintf(' ... point %d: %s',ipt,errptlsIstr); %#ok<AGROW>
end
str{end+1,1} = sprintf(' ... all points: %s',errptlsstr);
str{end+1,1} = '';

lObj.trackCrossValidateVizPrctiles(tblXVres,'prctiles',PTILES);
CrossValidResults(lObj,str,tblXVres);

function cbkTrackerStoreFullTrackingChanged(hObject, eventdata, handles)
sft = handles.labelerObj.tracker.storeFullTracking;
switch sft
  case StoreFullTrackingType.NONE
    handles.menu_track_store_full_tracking_dont_store.Checked = 'on';
    handles.menu_track_store_full_tracking_store_final_iteration.Checked = 'off';
    handles.menu_track_store_full_tracking_store_all_iterations.Checked = 'off';
    handles.menu_track_view_tracking_diagnostics.Enable = 'off';
  case StoreFullTrackingType.FINALITER
    handles.menu_track_store_full_tracking_dont_store.Checked = 'off';
    handles.menu_track_store_full_tracking_store_final_iteration.Checked = 'on';
    handles.menu_track_store_full_tracking_store_all_iterations.Checked = 'off';
    handles.menu_track_view_tracking_diagnostics.Enable = 'on';
  case StoreFullTrackingType.ALLITERS
    handles.menu_track_store_full_tracking_dont_store.Checked = 'off';
    handles.menu_track_store_full_tracking_store_final_iteration.Checked = 'off';
    handles.menu_track_store_full_tracking_store_all_iterations.Checked = 'on';
    handles.menu_track_view_tracking_diagnostics.Enable = 'on';
  otherwise
    assert(false);
end

function menu_track_clear_tracking_results_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
lObj.preProcInitData(); % legacy behavior not sure why; maybe b/c the user is prob wanting to increase avail mem
tObj = lObj.tracker;
tObj.clearTrackingResults();
msgbox('Tracking results cleared.','Done');

function menu_track_store_full_tracking_dont_store_Callback(hObject, eventdata, handles)
tObj = handles.labelerObj.tracker;
svr = tObj.showVizReplicates;
if svr
  qstr = 'Replicates will no longer by shown. OK?';
  resp = questdlg(qstr,'Tracking Storage','OK, continue','No, cancel','OK, continue');
  if isempty(resp)
    resp = 'No, cancel';
  end
  if strcmp(resp,'No, cancel')
    return;
  end
  tObj.showVizReplicates = false;
end
tObj.storeFullTracking = StoreFullTrackingType.NONE;

function menu_track_store_full_tracking_store_final_iteration_Callback(hObject, eventdata, handles)
tObj = handles.labelerObj.tracker;
tObj.storeFullTracking = StoreFullTrackingType.FINALITER;

function menu_track_store_full_tracking_store_all_iterations_Callback(hObject, eventdata, handles)
tObj = handles.labelerObj.tracker;
tObj.storeFullTracking = StoreFullTrackingType.ALLITERS;

function menu_track_view_tracking_diagnostics_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;

% Look for existing/open CPRVizTrackDiagsGUI
for i=1:numel(handles.depHandles)
  h = handles.depHandles(i);
  if isvalid(h) && strcmp(h.Tag,'figCPRVizTrackDiagsGUI')
    figure(h);
    return;
  end
end

lc = lObj.lblCore;
if ~isempty(lc) && ~lc.hideLabels
  warningNoTrace('LabelerGUI:hideLabels','Hiding labels.');
  lc.labelsHide();
end
hVizGUI = CPRVizTrackDiagsGUI(handles.labelerObj);
handles = addDepHandle(handles,hVizGUI);
guidata(handles.figure,handles);

function menu_track_track_and_export_Callback(hObject, eventdata, handles)
lObj = handles.labelerObj;
tm = getTrackMode(handles);
[tfok,rawtrkname] = lObj.getExportTrkRawnameUI();
if ~tfok
  return;
end
handles.labelerObj.trackAndExport(tm,'rawtrkname',rawtrkname);

function menu_track_export_current_movie_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
iMov = lObj.currMovie;
if iMov==0
  error('LabelerGUI:noMov','No movie currently set.');
end
[tfok,rawtrkname] = lObj.getExportTrkRawnameUI();
if ~tfok
  return;
end
lObj.trackExportResults(iMov,'rawtrkname',rawtrkname);

function menu_track_export_all_movies_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
nMov = lObj.nmoviesGTaware;
if nMov==0
  error('LabelerGUI:noMov','No movies in project.');
end
iMov = 1:nMov;
[tfok,rawtrkname] = lObj.getExportTrkRawnameUI();
if ~tfok
  return;
end
lObj.trackExportResults(iMov,'rawtrkname',rawtrkname);

function menu_track_set_labels_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
tObj = lObj.tracker;
if lObj.gtIsGTMode
  error('LabelerGUI:gt','Unsupported in GT mode.');
end
if ~isempty(tObj)
  xy = tObj.getPredictionCurrentFrame();
  xy = xy(:,:,lObj.currTarget); % "targets" treatment differs from below
  if any(isnan(xy(:)))
    fprintf('No predictions for current frame, not labeling.\n');
    return;
  end
  disp(xy);
  
  % AL20161219: possibly dangerous, assignLabelCoords prob was intended
  % only as a util method for subclasses rather than public API. This may
  % not do the right thing for some concrete LabelCores.
  lObj.lblCore.assignLabelCoords(xy);
else
  if lObj.nTrx>1
    error('LabelerGUI:setLabels','Unsupported for multiple targets.');
  end  
  iMov = lObj.currMovie;
  frm = lObj.currFrame;
  if iMov==0
    error('LabelerGUI:setLabels','No movie open.');
  end
  lpos2 = lObj.labeledpos2{iMov};
  assert(size(lpos2,4)==1); % "targets" treatment differs from above
  lpos2xy = lpos2(:,:,frm);
  lObj.labelPosSet(lpos2xy);
  
  lObj.lblCore.newFrame(frm,frm,1);
end

function menu_track_background_predict_start_Callback(hObject,eventdata,handles)
tObj = handles.labelerObj.tracker;
if tObj.asyncIsPrepared
  tObj.asyncStartBGWorker();
else
  if ~tObj.hasTrained
    errordlg('A tracker has not been trained.','Background Tracking');
    return;
  end
  tObj.asyncPrepare();
  tObj.asyncStartBGWorker();
end
  
function menu_track_background_predict_end_Callback(hObject,eventdata,handles)
tObj = handles.labelerObj.tracker;
if tObj.asyncIsPrepared
  tObj.asyncStopBGWorker();
else
  warndlg('Background worker is not running.','Background tracking');
end

function menu_track_background_predict_stats_Callback(hObject,eventdata,handles)
tObj = handles.labelerObj.tracker;
if tObj.asyncIsPrepared
  tObj.asyncComputeStats();
else
  warningNoTrace('LabelerGUI:bgTrack',...
    'No background tracking information available.','Background tracking');
end

function menu_evaluate_gtmode_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
gt = lObj.gtIsGTMode;
gtNew = ~gt;
lObj.gtSetGTMode(gtNew);
% hGTMgr = lObj.gdata.GTMgr;
if gtNew
  hMovMgr = lObj.gdata.movieMgr;
  hMovMgr.setVisible(true);
  figure(hMovMgr.hFig);
end

function menu_evaluate_gtcomputeperf_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
assert(lObj.gtIsGTMode);
% next three lines identical to GTManager:pbComputeGT_Callback
tblGTres = lObj.gtComputeGTPerformance();
msgbox('Assigned results in Labeler property ''gtTblRes''.');
lObj.gtReport();

function menu_evaluate_gtcomputeperfimported_Callback(hObject,eventdata,handles)
lObj = handles.labelerObj;
assert(lObj.gtIsGTMode);
% next three lines identical to GTManager:pbComputeGT_Callback
tblGTres = lObj.gtComputeGTPerformance('useLabels2',true);
msgbox('Assigned results in Labeler property ''gtTblRes''.');
lObj.gtReport();


  
function cbkGtIsGTModeChanged(src,evt)
lObj = src;
handles = lObj.gdata;
gt = lObj.gtIsGTMode;
onIffGT = onIff(gt);
handles.menu_evaluate_gtmode.Checked = onIffGT;
handles.menu_evaluate_gtcomputeperf.Visible = onIffGT;
handles.menu_evaluate_gtcomputeperfimported.Visible = onIffGT;
handles.txGTMode.Visible = onIffGT;
handles.GTMgr.Visible = onIffGT;
hlpGTUpdateAxHilite(lObj);

function figure_CloseRequestFcn(hObject, eventdata, handles)
CloseGUI(handles);

function CloseGUI(handles)
if hlpSave(handles.labelerObj)
  handles = clearDepHandles(handles);
  if isfield(handles,'movieMgr') && ~isempty(handles.movieMgr) ...
      && isvalid(handles.movieMgr)
    delete(handles.movieMgr);
  end  
  delete(handles.figure);
  delete(handles.labelerObj);
end

function pumInfo_Callback(hObject, eventdata, handles)
cprop = get(hObject,'Value');
handles.labelTLInfo.setCurProp(cprop);
hlpRemoveFocus(hObject,handles);

function pumInfo_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function play(hObject,handles,iconStrPlay,playMeth)
lObj = handles.labelerObj;
oc = onCleanup(@()playCleanup(hObject,handles,iconStrPlay));
if ~handles.isPlaying
  handles.isPlaying = true;
  guidata(hObject,handles);
  hObject.CData = Icons.ims.stop;
  lObj.(playMeth);
end
function playCleanup(hObject,handles,iconStrPlay)
hObject.CData = Icons.ims.(iconStrPlay);
handles.isPlaying = false;
guidata(hObject,handles);

function pbPlaySeg_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
play(hObject,handles,'playsegment','videoPlaySegment');

function pbPlay_Callback(hObject, eventdata, handles)
if ~checkProjAndMovieExist(handles)
  return;
end
play(hObject,handles,'play','videoPlay');

function tfok = checkProjAndMovieExist(handles)
tfok = false;
lObj = handles.labelerObj;
if ~lObj.hasProject
  return;
end
if ~lObj.hasMovie
  msgbox('There is no movie open.');
  return;
end
tfok = true;