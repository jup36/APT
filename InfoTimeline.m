classdef InfoTimeline < handle

  properties (Constant)
    TLPROPS = {'x' 'y' 'dx' 'dy' '|dx|' '|dy|' 'occluded'};
  end
  
%   % AL: Not using transparency for now due to perf issues on Linux
%   properties (Constant)
%     SELECTALPHA = 0.5;
%   end
  properties
    lObj % scalar Labeler handle
    hAx % scalar handle to timeline axis
    hCurrFrame % scalar line handle current frame
%     hMarked % scalar line handle, indicates marked frames
    hCMenuClearAll % scalar context menu
    hCMenuClearBout % scalar context menu

    hZoom % zoom handle for hAx
    hPan % pan handle "

    hPts % [npts] line handles
    npts % number of label points in current movie/timeline
    nfrm % number of frames "
    tldata % [nptsxnfrm] most recent data set/shown in setLabelsFull. this is NOT y-normalized
    
    listeners % [nlistener] col cell array of labeler prop listeners
    listenersTracker % col cell array of tracker listeners

    tracker % scalar LabelTracker obj
  end
  properties (SetObservable)
    props % [npropx3]. Col 1: pretty/display name. Col 2: Type, eg 'Labels', 'Labels2' or 'Tracks'. Col3: non-pretty name/id
    curprop % row index into props
  end
  properties
    jumpThreshold
    jumpCondition
  end
  
  %% Select
  properties (SetAccess=private)
    hSelIm % scalar image handle for selection
    selectOnStartFrm 
    isinit
  end
  properties (SetObservable)
    selectOn % scalar logical, if true, select "Pen" is down
  end
  
  %% GT/highlighting
  properties 
    hSegLineGT % scalar SegmentedLine
    hSegLineGTLbled % scalar SegmentedLine
  end
  
  %%
  properties (Dependent)
    prefs % projPrefs.InfoTimelines preferences substruct
  end
    
  methods
    function set.selectOn(obj,v)
      obj.selectOn = v;
      if ~obj.isinit %#ok<MCSUP>
        if v        
          obj.selectOnStartFrm = obj.lObj.currFrame; %#ok<MCSUP>
          obj.hCurrFrame.LineWidth = 3; %#ok<MCSUP>
        else
          obj.selectOnStartFrm = []; %#ok<MCSUP>
          obj.hCurrFrame.LineWidth = 0.5; %#ok<MCSUP>
          obj.setLabelerSelectedFrames();
        end
      end
    end
    function v = get.prefs(obj)
      v = obj.lObj.projPrefs.InfoTimelines;
    end
  end
  
  methods
    
    function obj = InfoTimeline(labeler,ax)
      obj.lObj = labeler;
      ax.Color = [0 0 0];
      ax.ButtonDownFcn = @(src,evt)obj.cbkBDF(src,evt);
      hold(ax,'on');
      obj.hAx = ax;
      obj.hCurrFrame = plot(ax,[nan nan],[0 1],'-','Color',[1 1 1],'hittest','off');
%       obj.hMarked = plot(ax,[nan nan],[nan nan],'-','Color',[1 1 0],'hittest','off');
      
      fig = ax.Parent;
      hZ = zoom(fig);
      setAxesZoomMotion(hZ,ax,'horizontal');
      obj.hZoom = hZ;
      hP = pan(fig);
      setAxesPanMotion(hP,ax,'horizontal');
      obj.hPan = hP;
      
      obj.hPts = [];
      obj.npts = nan;
      obj.nfrm = nan;
            
      listeners = cell(0,1);
      listeners{end+1,1} = addlistener(labeler,...
        {'labeledpos','labeledposMarked','labeledpostag','labeledposGT',...
         'labeledpostagGT'},... 
        'PostSet',@obj.cbkLabelUpdated);
      listeners{end+1,1} = addlistener(labeler,...
        'gtIsGTModeChanged',@obj.cbkGTIsGTModeUpdated);
      listeners{end+1,1} = addlistener(labeler,...
        'gtSuggUpdated',@obj.cbkGTSuggUpdated);
      listeners{end+1,1} = addlistener(labeler,...
        'gtSuggMFTableLbledUpdated',@obj.cbkGTSuggMFTableLbledUpdated);      
%       listeners{end+1,1} = addlistener(labeler,...
%         'labelMode','PostSet',@obj.cbkLabelMode);      
      obj.listeners = listeners;      
      obj.listenersTracker = cell(0,1);
      
      obj.tracker = [];
    
      props = InfoTimeline.TLPROPS(:);
      props(:,2) = {'Labels'};
      props(:,3) = props(:,1);
      props2 = props;      
      props2(:,1) = cellfun(@(x)sprintf('%s (imported)',x),props2(:,1),'uni',0);
      props2(:,2) = {'Labels2'};
      props = [props;props2];
      obj.props = props;    
      obj.curprop = 1;
      
      obj.jumpThreshold = nan;
      obj.jumpCondition = nan;
      
      obj.isinit = true;
      obj.hSelIm = [];
      obj.selectOn = false;
      obj.selectOnStartFrm = [];
      obj.hSegLineGT = SegmentedLine(ax);
      obj.hSegLineGTLbled = SegmentedLine(ax);
      obj.isinit = false;
      
      hCMenu = uicontextmenu('parent',ax.Parent,...
        'callback',@(src,evt)obj.cbkContextMenu(src,evt),...
        'UserData',struct('bouts',nan(0,2)));
      uimenu('Parent',hCMenu,'Label','Set number of frames shown',...
        'Callback',@(src,evt)obj.cbkSetNumFramesShown(src,evt));
      obj.hCMenuClearAll = uimenu('Parent',hCMenu,...
        'Label','Clear selection (N bouts)',...
        'UserData',struct('LabelPat','Clear selection (%d bouts)'),...
        'Callback',@(src,evt)obj.selectClearSelection());
      obj.hCMenuClearBout = uimenu('Parent',hCMenu,...
        'Label','Clear bout (frame M--N)',...
        'UserData',struct('LabelPat','Clear bout (frame %d-%d)','iBout',nan),...
        'Callback',@(src,evt)obj.cbkClearBout(src,evt));
      ax.UIContextMenu = hCMenu;
    end
    
    function delete(obj)
      deleteValidHandles(obj.hCurrFrame);
      obj.hCurrFrame = [];
%       deleteValidHandles(obj.hMarked);
%       obj.hMarked = [];
      if ~isempty(obj.hZoom)
        delete(obj.hZoom);
      end
      if ~isempty(obj.hPan)
        delete(obj.hPan);
      end
      deleteValidHandles(obj.hPts);
      obj.hPts = [];
      cellfun(@delete,obj.listeners);
      obj.listeners = [];
      cellfun(@delete,obj.listenersTracker);
      obj.listenersTracker = [];
      deleteValidHandles(obj.hSelIm);
      obj.hSelIm = [];
      deleteValidHandles(obj.hSegLineGT);
      obj.hSegLineGT = [];
      deleteValidHandles(obj.hSegLineGTLbled);
      obj.hSegLineGTLbled = [];
    end
    
  end  
  
  methods
    
    function initNewProject(obj)
      obj.npts = obj.lObj.nLabelPoints;

      deleteValidHandles(obj.hPts);
      obj.hPts = gobjects(obj.npts,1);
      colors = obj.lObj.labelPointsPlotInfo.Colors;
      ax = obj.hAx;
      for i=1:obj.npts
        obj.hPts(i) = plot(ax,nan,i,'.','linestyle','-','Color',colors(i,:),...
          'hittest','off');
      end
      
      prefsTL = obj.prefs;
      ax.XColor = prefsTL.XColor;
      dy = .01;
      ax.YLim = [0-dy 1+dy];
      
      set(obj.hCurrFrame,'XData',[nan nan],'ZData',[1 1]);
    end
    
    function initNewMovie(obj)
      if obj.lObj.hasMovie
        obj.nfrm = obj.lObj.nframes;
      else
        obj.nfrm = 1;
      end
      ax = obj.hAx;
      prefsTL = obj.prefs;
      ax.XTick = 0:prefsTL.dXTick:obj.nfrm;

      obj.selectInit();
      
      xlims = [1 obj.nfrm];
      SEGLINEYLOC = 1;
      sPV = struct('LineWidth',5,'Color',AxesHighlightManager.ORANGE);
      sPVLbled = struct('LineWidth',5,'Color',AxesHighlightManager.ORANGE/2);
      obj.hSegLineGT.init(xlims,SEGLINEYLOC,sPV);
      obj.hSegLineGTLbled.init(xlims,SEGLINEYLOC,sPVLbled);
      
      cbkGTSuggUpdated(obj,[],[]);
    end
        
    function setTracker(obj,tracker)
      obj.tracker = tracker;
      
      % Break down existing props; eliminate existing tracker-props. We
      % also prefer tracker-props to come before labels2 props.
      pmat = obj.props;
      src = pmat(:,2);
      tfLabels = strcmp(src,'Labels');
      tfTracks = strcmp(src,'Tracks'); % will be deleted
      tfLabels2 = strcmp(src,'Labels2');
      assert(all(tfLabels+tfTracks+tfLabels2==1));

      cellfun(@delete,obj.listenersTracker);
      obj.listenersTracker = cell(0,1);      
      if isempty(tracker)
        obj.props = [pmat(tfLabels,:); pmat(tfLabels2,:)];
      else
        propList = tracker.propList();
        pmatnew = arrayfun(...
          @(x){sprintf('%s (tracked)',propList{x}) 'Tracks' propList{x}},...
          (1:numel(propList))','uni',0);
        pmatnew = cat(1,pmatnew{:});
        obj.props = [pmat(tfLabels,:); pmatnew; pmat(tfLabels2,:)];
        
        cellfun(@delete,obj.listenersTracker);
        obj.listenersTracker{end+1,1} = addlistener(tracker,...
          'newTrackingResults',@obj.cbkLabelUpdated);
      end
    end
    
    function setLabelsFull(obj)
      % Get data and set .hPts, .hMarked
      
      if isnan(obj.npts), return; end
      
      dat = obj.getDataCurrMovTgt(); % [nptsxnfrm]
      dat(isinf(dat)) = nan;
      datnonnan = dat(~isnan(dat));

      obj.tldata = dat;
      
      if isempty(datnonnan)
        for i=1:obj.npts
          set(obj.hPts(i),'XData',nan,'YData',nan);
        end
%         set(obj.hMarked,'XData',nan,'YData',nan);
        return;
      end

      y1 = min(datnonnan(:));
      y2 = max(datnonnan(:));
      dy = max(y2-y1,eps);
      lposNorm = (dat-y1)/dy; % Either nan, or in [0,1]
      x = 1:size(lposNorm,2);
      for i=1:obj.npts
        set(obj.hPts(i),'XData',x,'YData',lposNorm(i,:));
      end
      
%       markedFrms = find(any(obj.getMarkedDataCurrMovTgt(),1));
%       xxm = repmat(markedFrms,[3 1]);
%       xxm = xxm(:)+0.05; 
      % slightly off so that both current frame and labeled frame are both
      % visible.
%       yym = repmat([0 1 nan],[1 size(markedFrms,2)]);
%       set(obj.hMarked,'XData',xxm(:),'YData',yym(:));
    end
    
    function setLabelsFrame(obj,frm)
      % frm: [n] frame indices. Optional. If not supplied, defaults to
      % labeler.currFrame
      
      % AL20170616: Originally, timeline was not intended to listen
      % directly to Labeler.labeledpos etc; instead, notification of change
      % in labels was done by piggy-backing on Labeler.updateFrameTable*
      % (which explicitly calls this method). However, obj is now listening 
      % directly to lObj.labeledpos so this method is obsolete. Leave stub 
      % here in case need to go back to piggy-backing on
      % .updateFrameTable* eg for performance reasons.
            
%       lpos = obj.getDataCurrMovTgt();
%       for i=1:obj.npts
%         h = obj.hPts(i);
%         set(h,'XData',1:size(lpos,2),'YData',lpos(i,:));
%       end
    end
    
    function newFrame(obj,frm)
      % Respond to new .lObj.currFrame
      
      if isnan(obj.npts), return; end
            
      r = obj.prefs.FrameRadius;
      x0 = frm-r; %max(frm-r,1);
      x1 = frm+r; %min(frm+r,obj.nfrm);
      obj.hAx.XLim = [x0 x1];
      set(obj.hCurrFrame,'XData',[frm frm]);
      
      if obj.selectOn
        f0 = obj.selectOnStartFrm;
        f1 = frm;
        if f1>f0
          idx = f0:f1;
        else
          idx = f1:f0;
        end
        obj.hSelIm.CData(:,idx) = 1;
      end
    end
    
    function newTarget(obj)
      obj.setLabelsFull();
    end

    function selectInit(obj)
      if obj.lObj.isinit || isnan(obj.nfrm), return; end

      deleteValidHandles(obj.hSelIm);
      obj.hSelIm = image(1:obj.nfrm,0.5,uint8(zeros(1,obj.nfrm)),...
        'parent',obj.hAx,'HitTest','off',...
        'CDataMapping','direct');

      obj.selectOn = false;
      obj.selectOnStartFrm = [];
      colorTBSelect = obj.lObj.gdata.tbTLSelectMode.BackgroundColor;
      colormap(obj.hAx,[0 0 0;colorTBSelect]);
      
      obj.setLabelerSelectedFrames();
    end

    function bouts = selectGetSelection(obj)
      % Get currently selected bouts (can be noncontiguous)
      %
      % bouts: [nBout x 2]. col1 is startframe, col2 is one-past-endframe

      cdata = obj.hSelIm.CData;
      [sp,ep] = get_interval_ends(cdata);
      bouts = [sp(:) ep(:)];
    end
    
    function selectClearSelection(obj)
      obj.selectInit();
    end
        
    function setJumpParams(obj)
      % GUI to get jump parameters,
      f = figure('Visible','on','Position',[360,500,200,90],...
        'MenuBar','None','ToolBar','None');
      tbottom = 70;
      uicontrol('Style','text',...
                   'String','Jump To:','Value',1,'Position',[10,tbottom,190,20]);
      
      ibottom = 50;           
      hprop = uicontrol('Style','Text',...
                   'String','drasdgx','Value',1,'Position',[10,ibottom-2,90,20],...
                   'HorizontalAlignment','left');
      hprope = get(hprop,'Extent');
      st = hprope(3) + 15;
      hCondition = uicontrol('Style','popupmenu',...
                   'String',{'>','<='},'Value',1,'Position',[st,ibottom,40,20]);
      hval = uicontrol('Style','edit',...
                   'String','0','Position',[st+55,ibottom-2,30,20]);           
      bbottom = 10;


      uicontrol('Style','pushbutton',...
                   'String','Cancel','Position',[30,bbottom,60,30],'Callback',{fcancel,f});
      uicontrol('Style','pushbutton',...
                   'String','Done','Position',[110,bbottom,60,30],...
                   'Callback',{fapply,f,hCondition,hval,obj});
                 
      function fcancel(~,~,f)
        delete(f);
      end
      
      function fapply(~,~,f,hCondition,hval,obj) 
        tr = str2double(get(hval,'String'));
        if isnan(tr)
          warndlg('Enter valid numerical value');
          return;
        end
        obj.jumpThreshold = tr;
        obj.jumpCondition = 2*get(hCondition,'Value')-3;
        delete(f);
      end
    end
    
  end
  
  methods %getters setters
    function props = getPropsDisp(obj)
      props = obj.props(:,1);
    end
    function setCurProp(obj,iprop)
      obj.curprop = iprop;
      obj.setLabelsFull();
    end    
  end
    
  %% Private methods
  methods (Access=private) % callbacks
    function cbkBDF(obj,src,evt) %#ok<INUSL>
      if ~(obj.lObj.hasProject && obj.lObj.hasMovie)
        return;
      end

      if evt.Button==1
        % Navigate to clicked frame
        
        pos = get(obj.hAx,'CurrentPoint');
        frm = round(pos(1,1));
        frm = min(max(frm,1),obj.nfrm);
        obj.lObj.setFrame(frm);
      end
    end
%     function cbkLabelMode(obj,src,evt) %#ok<INUSD>
% %       onoff = onIff(obj.lObj.labelMode==LabelMode.ERRORCORRECT);
%       onoff = 'off';
%       set(obj.hMarked,'Visible',onoff);
%     end
    function cbkLabelUpdated(obj,src,~) %#ok<INUSD>
      if ~obj.lObj.isinit
        obj.setLabelsFull;
      end
    end
    function cbkSetNumFramesShown(obj,src,evt) %#ok<INUSD>
      frmRad = obj.prefs.FrameRadius;
      aswr = inputdlg('Number of frames','Timeline',1,{num2str(2*frmRad)});
      if ~isempty(aswr)
        nframes = str2double(aswr{1});
        validateattributes(nframes,{'numeric'},{'positive' 'integer'});
        obj.lObj.projPrefs.InfoTimelines.FrameRadius = round(nframes/2);
        obj.newFrame(obj.lObj.currFrame);
      end
    end
    function cbkContextMenu(obj,src,evt)
      bouts = obj.selectGetSelection;
      nBouts = size(bouts,1);
      src.UserData.bouts = bouts;

      % Fill in bout number in "clear all" menu item
      hMnuClearAll = obj.hCMenuClearAll;
      hMnuClearAll.Label = sprintf(hMnuClearAll.UserData.LabelPat,nBouts);
      
      % figure out if user clicked within a bout
      pos = get(obj.hAx,'CurrentPoint');
      frmClick = pos(1);
      tf = bouts(:,1)<=frmClick & frmClick<=bouts(:,2);
      iBout = find(tf);
      tfClickedInBout = ~isempty(iBout);
      hMnuClearBout = obj.hCMenuClearBout;
      hMnuClearBout.Visible = onIff(tfClickedInBout);
      if tfClickedInBout
        assert(isscalar(iBout));
        hMnuClearBout.Label = sprintf(hMnuClearBout.UserData.LabelPat,...
                                      bouts(iBout,1),bouts(iBout,2)-1);
        hMnuClearBout.UserData.iBout = iBout;  % store bout that user clicked in                                   
      end
    end
    function cbkClearBout(obj,src,evt)
      % Prob should have a select* method, for now just do everything here
      iBout = src.UserData.iBout;
      boutsAll = src.Parent.UserData.bouts;
      bout = boutsAll(iBout,:);
      obj.hSelIm.CData(:,bout(1):bout(2)-1) = 0;
      obj.setLabelerSelectedFrames();
    end    
    function cbkGTIsGTModeUpdated(obj,src,evt)
      lblObj = obj.lObj;
      gt = lblObj.gtIsGTMode;
      if gt
        obj.cbkGTSuggUpdated([],[]);
      end
      onOff = onIff(gt);
      obj.hSegLineGT.setVisible(onOff);
      obj.hSegLineGTLbled.setVisible(onOff);
    end
    function cbkGTSuggUpdated(obj,src,evt)
      % full update to any change to labeler.gtSuggMFTable*
      
      lblObj = obj.lObj;
      if lblObj.isinit || ~lblObj.hasMovie || ~lblObj.gtIsGTMode
        % segLines are not visible; more importantly, cannot set segLine
        % highlighting based on suggestions in current movie
        return;
      end
      
      % find rows for current movie
      tblLbled = table(lblObj.gtSuggMFTableLbled,'variableNames',{'hasLbl'});
      tbl = [lblObj.gtSuggMFTable tblLbled];
      mIdx = lblObj.currMovIdx;
      tf = mIdx==tbl.mov;
      tblCurrMov = tbl(tf,:); % current mov, various frm/tgts
      
      % for hSegLineGT, we highlight any/all frames (regardless of, or across all, targets)
      frmsOn = tblCurrMov.frm; % could contain repeat frames (across diff targets)
      obj.hSegLineGT.setOnAtOnly(frmsOn);
      
      % For hSegLineGTLbled, we turn on a given frame only if all
      % targets/rows for that frame are labeled.
      tblRes = rowfun(@(zzHasLbl)all(zzHasLbl),tblCurrMov,...
        'groupingVariables',{'frm'},'inputVariables','hasLbl',...
        'outputVariableNames',{'allTgtsLbled'});
      frmsAllTgtsLbled = tblRes.frm(tblRes.allTgtsLbled);
      obj.hSegLineGTLbled.setOnAtOnly(frmsAllTgtsLbled);
    end
    function cbkGTSuggMFTableLbledUpdated(obj,src,evt)
      % React to incremental update to labeler.gtSuggMFTableLbled
      
      lblObj = obj.lObj;
      if ~lblObj.gtIsGTMode
        % segLines are not visible,; more importantly, cannot set segLine
        % highlighting based on suggestions in current movie
        return;
      end
      
      % find rows for current movie/frm
      tbl = lblObj.gtSuggMFTable;
      currFrm = lblObj.currFrame;
      tfCurrMovFrm = tbl.mov==lblObj.currMovIdx & tbl.frm==currFrm;
      tfLbled = lblObj.gtSuggMFTableLbled;
      tfLbledCurrMovFrm = tfLbled(tfCurrMovFrm,:);
      tfHiliteOn = numel(tfLbledCurrMovFrm)>0 && all(tfLbledCurrMovFrm);
      obj.hSegLineGTLbled.setOnOffAt(currFrm,tfHiliteOn);
    end
  end

  methods (Static) % util
    function dmat = getDataFromLpos(lpos,lpostag,pcode,iTgt)
      % lpos: [npts x 2 x nfrm x ntgt] label array as in
      %   lObj.labeledpos{iMov}
      % lpostag: [npts x nfrm x ntgt] logical as in lObj.labeledpostag{iMov}
      % pcode: name/id of data to extract
      % iTgt: current target
      %
      % dmat: [npts x nfrm] data matrix for pcode, extracted from lpos
      
      npts = size(lpos,1); % should equal obj.npts
      nfrm = size(lpos,3); % should equal obj.nfrm
      
      switch pcode
        case 'x'
          dmat = reshape(lpos(:,1,:,iTgt),npts,nfrm);
        case 'y'
          dmat = reshape(lpos(:,2,:,iTgt),npts,nfrm);
        case 'dx'
          dmat = reshape(lpos(:,1,:,iTgt),npts,nfrm);
          dmat = diff(dmat,1,2);
          dmat(:,end+1) = nan;
        case 'dy'
          dmat = reshape(lpos(:,2,:,iTgt),npts,nfrm);
          dmat = diff(dmat,1,2);
          dmat(:,end+1) = nan;
        case '|dx|'
          dmat = reshape(lpos(:,1,:,iTgt),npts,nfrm);
          dmat = abs(diff(dmat,1,2));
          dmat(:,end+1) = nan;
        case '|dy|'
          dmat = reshape(lpos(:,2,:,iTgt),npts,nfrm);
          dmat = abs(diff(dmat,1,2));
          dmat(:,end+1) = nan;
        case 'occluded'
          dmat = double(lpostag(:,:,iTgt));
        otherwise
          warningNoTrace('Unknown property to display in timeline.');
          dmat = nan(size(lpos,1),size(lpos,3));
      end
    end
  end
  
  methods (Access=private)
    function setLabelerSelectedFrames(obj)
      % For the moment Labeler owns the property-of-record on what frames
      % are set
      selFrames = bouts2frames(obj.selectGetSelection);
      obj.lObj.setSelectedFrames(selFrames);
    end

    function data = getDataCurrMovTgt(obj)
      % lpos: [nptsxnfrm]
      
      pndx = obj.curprop;
      ptype = obj.props{pndx,2};
      pcode = obj.props{pndx,3};
      labeler = obj.lObj;
      iMov = labeler.currMovie;
      iTgt = labeler.currTarget;
      
      if iMov==0
        data = nan(obj.npts,1);
      else
        switch ptype
          case 'Labels'
            lpos = labeler.labeledposGTaware{iMov};
            lpostag = labeler.labeledpostagGTaware{iMov};            
            data = InfoTimeline.getDataFromLpos(lpos,lpostag,pcode,iTgt);
          case 'Labels2'            
            lpos = labeler.labeledpos2GTaware{iMov};
            lpostag = cell(obj.npts,labeler.nframes,labeler.nTargets);
            data = InfoTimeline.getDataFromLpos(lpos,lpostag,pcode,iTgt);            
          case 'Tracks'
            data = obj.tracker.getPropValues(pcode);
        end
        szassert(data,[obj.npts obj.nfrm]);
      end
    end
    
    function lpos = getMarkedDataCurrMovTgt(obj)
      % lpos: [nptsxnfrm]
      
      labeler = obj.lObj;
      iMov = labeler.currMovie;
      if iMov>0
        if ~labeler.gtIsGTMode
          iTgt = labeler.currTarget;
          lpos = squeeze(labeler.labeledposMarked{iMov}(:,:,iTgt)); % AL: squeeze seems unnec
        else
          lpos = false(labeler.nLabelPoints,labeler.nframes);
        end
      else
        lpos = false(labeler.nLabelPoints,1);
      end
    end
    
    function nxtFrm = findFrame(obj,dr,curFr)
      % Finds the next or previous frame which satisfy conditions.
      % dr = 0 is back, 1 is forward
      nxtFrm = nan;
      if isnan(obj.jumpThreshold)
        warndlg('Threhold value is not for navigation');
        obj.thresholdGUI();
        if isnan(obj.jumpThreshold)
          return;
        end
      end
      
      data = obj.getDataCurrMovTgt();
      if obj.jumpCondition > 0
        locs = any(data>obj.jumpThreshold,1);
      else
        locs = any(data<=obj.jumpThreshold,1);
      end
      
      if dr > 0.5
        locs = locs(curFr:end);
        nxtlocs = find( (~locs(1:end-1))&(locs(2:end)),1);
        if isempty(nxtlocs)
          return;
        end
        nxtFrm = curFr + nxtlocs - 1;
      else
        locs = locs(1:curFr);
        nxtlocs = find( (locs(1:end-1))&(~locs(2:end)),1,'last');
        if isempty(nxtlocs)
          return;
        end
        nxtFrm = nxtlocs;
      end
    end
  end
  
end
