function varargout = ProjectSetup(varargin)
% PROJECTSETUP MATLAB code for ProjectSetup.fig
%      PROJECTSETUP, by itself, creates a new PROJECTSETUP or raises the existing
%      singleton*.
%
%      H = PROJECTSETUP returns the handle to a new PROJECTSETUP or the handle to
%      the existing singleton*.
%
%      PROJECTSETUP('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in PROJECTSETUP.M with the given input arguments.
%
%      PROJECTSETUP('Property','Value',...) creates a new PROJECTSETUP or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before ProjectSetup_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to ProjectSetup_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help ProjectSetup

% Last Modified by GUIDE v2.5 22-Aug-2016 15:35:39

% Begin initialization code - DO NOT EDIT
gui_Singleton = 0;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @ProjectSetup_OpeningFcn, ...
                   'gui_OutputFcn',  @ProjectSetup_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

% PROJECT CONFIGURATION/SETUP NOTES
% 20160815
% 
% A _project configuration_ is the stuff in pref.default.yaml. It is 
% comprised of:
%
% 1. Core per-project info: number/names of views, number/names of points.
% 2. More cosmetic per-project info: how lines/markers look, frame 
% increments in various situations, etc.
% 3. Tracker specification and config.
% 4. More application-level preferences, like keyboard shortcut choices. 
% Strictly speaking these could be separated out but for now just lump them 
% in. (Plus, who knows what turns out to be useful when configurable
% per-project.)
%
% If you have a project configuration, you can create/init a new, "blank"
% project.
%
% A _project_ is comprised of:
% 1. A project configuration
% 2. Moviefilenames, trxfilenames, filename macros, file metadata
% 3. (Optional) view calibration info, view calibration file
% 4. Label data (labels, timestamps, tags, flags)
% 5. UI state: current movie/frame/target, labelMode, image colormap etc
%
% The first time you need a project configuration, the stuff in
% pref.default.yaml is used. In all subsequent instances, you start off
% with your most recent configuration.
%
% Once a project is created, much/most of the configuration info is
% mutable. For instance, you can rename points, change labelModes, change
% trackers, change plot cosmetics, etc. A few things are currently 
% immutable, such as the number of labeling points. When a project is
% saved, the saved configuration is generated from the
% Labeler-state-at-that-time, which may differ from the project's initial
% configuration. 
%
% Later, if application-wide preferences are desired/added, these can
% override parts of the project configuration as appropriate.
%
% Labeler actions:
% - Create a new/blank project from a configuration.
% - Get the current configuration.
% - Load an existing project (which contains a configuration).
% - Save a project -- i) get current config, and ii) create project.

% --- Executes just before ProjectSetup is made visible.
%
% Modal dialog. Generates project configuration struct
%
% cfg = ProjectSetup(); 
% cfg = ProjectSetup(hParentFig); % centered on hParentFig
function ProjectSetup_OpeningFcn(hObject, eventdata, handles, varargin)

h1 = findall(handles.figure1,'-property','Units');
set(h1,'Units','Normalized');

if numel(varargin)>=1
  hParentFig = varargin{1};
  if ~ishandle(hParentFig)
    error('ProjectSetup:arg','Expected first argument to be a figure handle.');
  end
  centerOnParentFigure(hObject,hParentFig);
end  
  
handles.output = [];

% init PUMs that depend only on codebase
lms = enumeration('LabelMode');
lmStrs = arrayfun(@(x)x.prettyString,lms,'uni',0);
handles.pumLabelingMode.String = lmStrs;
handles.pumLabelingMode.UserData = lms;
trackers = LabelTracker.findAllSubclasses;
trackers = [{'None'};trackers];
handles.pumTracking.String = trackers;

handles.propsPane = [];

% init ui state
cfg = Labeler.cfgGetLastProjectConfig;
handles = setCurrentConfig(handles,cfg);
handles.propsPane.Position(4) = handles.propsPane.Position(3); % by default table is slightly bigger than panel for some reason
handles = advModeCollapse(handles);

guidata(hObject, handles);

% UIWAIT makes ProjectSetup wait for user response (see UIRESUME)
uiwait(handles.figure1);

function varargout = ProjectSetup_OutputFcn(hObject, eventdata, handles) 
varargout{1} = handles.output;
delete(handles.figure1);

function cfg = genCurrentConfig(handles)
% Generate config from the current UI state

ad = getappdata(handles.figure1);
cfg = ad.mirror;

assert(numel(fieldnames(cfg.ViewNames))==handles.nViews);
assert(numel(fieldnames(cfg.LabelPointNames))==handles.nPoints);
cfg.NumViews = handles.nViews;
cfg.NumLabelPoints = handles.nPoints;
cfg.ViewNames = struct2cell(cfg.ViewNames);
cfg.LabelPointNames = struct2cell(cfg.LabelPointNames);
pumLM = handles.pumLabelingMode;
lmVal = pumLM.Value;
cfg.LabelMode = char(pumLM.UserData(lmVal));
pumTrk = handles.pumTracking;
tracker = pumTrk.String{pumTrk.Value};
cfg.Track.Enable = ~strcmpi(tracker,'none');
cfg.Track.Type = tracker;

function handles = setCurrentConfig(handles,cfg)
% Set given config on controls

% we store these two props on handles in order to be able to revert; 
% data/model is split between i) primary UIcontrols and ii) adv panel 
handles.nViews = cfg.NumViews; 
handles.nPoints = cfg.NumLabelPoints;
set(handles.etNumberOfViews,'string',num2str(handles.nViews));
set(handles.etNumberOfPoints,'string',num2str(handles.nPoints));

pumLM = handles.pumLabelingMode;
[tf,val] = ismember(cfg.LabelMode,arrayfun(@char,pumLM.UserData,'uni',0));
if ~tf
  % should never happen 
  val = 1; % NONE
end
pumLM.Value = val;

pumTrk = handles.pumTracking;
if cfg.Track.Enable 
  [tf,val] = ismember(cfg.Track.Type,pumTrk.String);
  if ~tf
    % unexpected but maybe not impossible due to path
    val = 1; % None
  end
else
  val = 1;
end
pumTrk.Value = val;

sMirror = cfg2mirror(cfg);
if ~isempty(handles.propsPane) && ishandle(handles.propsPane)
  delete(handles.propsPane);
end
handles.propsPane = propertiesGUI(handles.pnlAdvanced,sMirror);

function sMirror = cfg2mirror(cfg)
% Convert true/full data struct to 'mirror' struct for adv table. (The term
% 'mirror' comes from implementation detail of adv table/propertiesGUI.)

nViews = cfg.NumViews;
nPoints = cfg.NumLabelPoints;

cfg = Labeler.cfgDefaultOrder(cfg);
sMirror = rmfield(cfg,{'NumViews' 'NumLabelPoints' 'LabelMode'});
sMirror.Track = rmfield(sMirror.Track,{'Enable' 'Type'});

assert(isempty(sMirror.ViewNames) || numel(sMirror.ViewNames)==nViews);
flds = arrayfun(@(i)sprintf('view%d',i),(1:nViews)','uni',0);
if isempty(sMirror.ViewNames)
  vals = repmat({''},nViews,1);
else
  vals = sMirror.ViewNames;
end
sMirror.ViewNames = cell2struct(vals,flds,1);

assert(isempty(sMirror.LabelPointNames) || numel(sMirror.LabelPointNames)==nPoints);
flds = arrayfun(@(i)sprintf('point%d',i),(1:nPoints)','uni',0);
if isempty(sMirror.LabelPointNames)
  vals = repmat({''},nPoints,1);
else
  vals = sMirror.LabelPointNames;
end
sMirror.LabelPointNames = cell2struct(vals,flds,1);

function sMirror = hlpAugmentOrTruncNameField(sMirror,fld,subfld,n)
v = sMirror.(fld);
flds = fieldnames(v);
nflds = numel(flds);
if nflds>n
  v = rmfield(v,flds(n+1:end));
elseif nflds<n
  for i=nflds+1:n
	v.([subfld num2str(i)]) = '';
  end
end
sMirror.(fld) = v;

function advTableRefresh(handles)
ad = getappdata(handles.figure1);
sMirror = ad.mirror;
sMirror = hlpAugmentOrTruncNameField(sMirror,'ViewNames','view',handles.nViews);
sMirror = hlpAugmentOrTruncNameField(sMirror,'LabelPointNames','point',handles.nPoints);
if ~isempty(handles.propsPane) && ishandle(handles.propsPane)
  delete(handles.propsPane);
  handles.propsPane = [];
end  
handles.propsPane = propertiesGUI(handles.pnlAdvanced,sMirror);
guidata(handles.figure1,handles);

function handles = advModeExpand(handles)
h1 = findall(handles.figure1,'-property','Units');
set(h1,'Units','pixels');
posRight = handles.landmarkRight.Position;
posRight = posRight(1)+posRight(3);
pos = handles.figure1.Position;
pos(3) = posRight;
handles.figure1.Position = pos;
set(h1,'Units','normalized');
handles.advancedOn = true;
handles.pbAdvanced.String = '< Basic';

function handles = advModeCollapse(handles)
h1 = findall(handles.figure1,'-property','Units');
set(h1,'Units','pixels');
posMid = handles.landmarkMid.Position;
posMid = posMid(1)+posMid(3)/2;
pos = handles.figure1.Position;
pos(3) = posMid;
handles.figure1.Position = pos;
set(h1,'Units','normalized');
handles.advancedOn = false;
handles.pbAdvanced.String = 'Advanced >';

function handles = advModeToggle(handles)
if handles.advancedOn
  handles = advModeCollapse(handles);
else
  handles = advModeExpand(handles);
end

function etProjectName_Callback(hObject, eventdata, handles)
function etNumberOfPoints_Callback(hObject, eventdata, handles)
val = str2double(hObject.String);
if floor(val)==val && val>=1
  handles.nPoints = val;
  guidata(hObject,handles);
else
  hObject.String = handles.nPoints;
end
advTableRefresh(handles);
function etNumberOfViews_Callback(hObject, eventdata, handles)
val = str2double(hObject.String);
if floor(val)==val && val>=1
  handles.nViews = val;
  guidata(hObject,handles);
else
  hObject.String = handles.nViews;
end
advTableRefresh(handles);
function pumLabelingMode_Callback(hObject, eventdata, handles)
function pumTracking_Callback(hObject, eventdata, handles)
function pbCreateProject_Callback(hObject, eventdata, handles)
cfg = genCurrentConfig(handles);
cfg.ProjectName = handles.etProjectName.String;
handles.output = cfg;
guidata(handles.figure1,handles);
close(handles.figure1);
function pbCancel_Callback(hObject, eventdata, handles)
handles.output = [];
guidata(handles.figure1,handles);
close(handles.figure1);
function pbCollapseNames_Callback(hObject, eventdata, handles)
function pbAdvanced_Callback(hObject, eventdata, handles)
handles = advModeToggle(handles);
guidata(handles.figure1,handles);
function pbCopySettingsFrom_Callback(hObject, eventdata, handles)
lastLblFile = RC.getprop('lastLblFile');
if isempty(lastLblFile)
  lastLblFile = pwd;
end
[fname,pth] = uigetfile('*.lbl','Select project file',lastLblFile);
if isequal(fname,0)
  return;
end
lbl = load(fullfile(pth,fname),'-mat');
lbl = Labeler.lblModernize(lbl);
cfg = lbl.cfg;
handles = setCurrentConfig(handles,cfg);
guidata(handles.figure1,handles);

function figure1_CloseRequestFcn(hObject, eventdata, handles)
if isequal(get(hObject,'waitstatus'),'waiting')
% The GUI is still in UIWAIT, us UIRESUME
  uiresume(hObject);
else  
  delete(hObject);
end