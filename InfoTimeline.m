classdef InfoTimeline < handle

  properties (Constant)
    SELECTALPHA = 0.5;
  end
  properties
    lObj % scalar Labeler handle
    hAx % scalar handle to timeline axis
    hCurrFrame % scalar line handle current frame
    hMarked % scalar line handle, indicates marked frames
    hCMenuClearAll % scalar context menu
    hCMenuClearBout % scalar context menu

    hZoom % zoom handle for hAx
    hPan % pan handle "

    hPts % [npts] line handles
    npts % number of label points in current movie/timeline
    nfrm % number of frames "
    
    listeners % [nlistener] col cell array of labeler prop listeners

    tracker % scalar LabelTracker obj
  end
  properties (SetObservable)
    props % [npropx3]. Col 1: pretty/display name. Col 2: Type, eg 'Labels', 'Labels2' or 'Tracks'. Col3: non-pretty name/id
    curprop % str
  end
  properties
    jumpThreshold
    jumpCondition
  end
  properties (SetAccess=private)
    hSelIm % scalar image handle for selection
    selectOnStartFrm 
  end
  properties (SetObservable)
    selectOn % scalar logical, if true, select "Pen" is down
  end
  properties (Dependent)
    prefs % projPrefs.InfoTimelines preferences substruct
  end
    
  methods
    function set.selectOn(obj,v)
      obj.selectOn = v;
      if v        
        obj.selectOnStartFrm = obj.lObj.currFrame; %#ok<MCSUP>
        obj.hCurrFrame.LineWidth = 3; %#ok<MCSUP>
      else
        obj.selectOnStartFrm = []; %#ok<MCSUP>
        obj.hCurrFrame.LineWidth = 0.5; %#ok<MCSUP>
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
      obj.hMarked = plot(ax,[nan nan],[nan nan],'-','Color',[1 1 0],'hittest','off');
      
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
        {'labeledpos','labeledposMarked','labeledpostag'},...
        'PostSet',@obj.cbkLabelUpdated);
      listeners{end+1,1} = addlistener(labeler,...
        'labelMode','PostSet',@obj.cbkLabelMode);      
      obj.listeners = listeners;
      
      obj.tracker = [];
      
      obj.props = {};
      props1(:,1) = {'x','y','dx','dy','|dx|','|dy|','occluded'};
      props1(:,2) = {'Labels'};
      props1(:,3) = {'x','y','dx','dy','|dx|','|dy|','occluded'};
      props2(:,1) = {'x (pred)','y (pred)','dx (pred)','dy (pred)','|dx| (pred)','|dy| (pred)'};
      props2(:,2) = {'Labels2'};
      props2(:,3) = {'x','y','dx','dy','|dx|','|dy|'};
      obj.props = [props1;props2];
      obj.curprop = obj.props{1,1};
      
      obj.jumpThreshold = nan;
      obj.jumpCondition = nan;
      
      obj.hSelIm = [];
      obj.selectOn = false;
      obj.selectOnStartFrm = [];
      
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
      deleteValidHandles(obj.hMarked);
      obj.hMarked = [];
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
      deleteValidHandles(obj.hSelIm);
      obj.hSelIm = [];
    end
    
  end  
  
  methods
    
    function initNewMovie(obj)
      % react to new current movie in Labeler

      obj.npts = obj.lObj.nLabelPoints;
      obj.nfrm = obj.lObj.nframes;

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
      ax.XTick = 0:prefsTL.dXTick:obj.nfrm;
      ax.YLim = [0 1];
      
      set(obj.hCurrFrame,'XData',[nan nan],'ZData',[1 1]);
      
      obj.selectInit();
    end
    
    function setTracker(obj,tracker)
      obj.tracker = tracker;
      newprops = tracker.propList();
      for ndx = 1:numel(newprops)
        obj.props(end+1,1) = newprops{count};
        obj.props(end,2) = 'Tracks';
        obj.props(end,3) = newprops{count};
      end
    end
    
    function setLabelsFull(obj)
      % Get data and set .hPts, .hMarked
      
      if isnan(obj.npts), return; end
      
      lpos = obj.getDataCurrMovTgt(); % [nptsxnfrm]
      y1 = min(lpos(:));
      y2 = max(lpos(:));
      dy = max(y2-y1,eps);
      lposNorm = (lpos-y1)/dy; % in [0,1]
      x = 1:size(lposNorm,2);
      for i=1:obj.npts
        set(obj.hPts(i),'XData',x,'YData',lposNorm(i,:));
      end
      
      markedFrms = find(any(obj.getMarkedDataCurrMovTgt(),1));
      xxm = repmat(markedFrms,[3 1]);
      xxm = xxm(:)+0.05; 
      % slightly off so that both current frame and labeled frame are both
      % visible.
      yym = repmat([0 1 nan],[1 size(markedFrms,2)]);
      set(obj.hMarked,'XData',xxm(:),'YData',yym(:));
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
      if obj.lObj.isinit, return; end

      obj.selectOn = false;
      obj.selectOnStartFrm = [];
      deleteValidHandles(obj.hSelIm);
      obj.hSelIm = image(1:obj.nfrm,0.5,uint8(zeros(1,obj.nfrm)),...
        'parent',obj.hAx,'alphadata',obj.SELECTALPHA,'HitTest','off',...
        'CDataMapping','direct');
      colorTBSelect = obj.lObj.gdata.tbTLSelectMode.BackgroundColor;
      colormap(obj.hAx,[0 0 0;colorTBSelect]);
    end

    function bouts = selectGetSelection(obj)
      % Get currently selected bouts (can be noncontiguous)
      %
      % bouts: [nBout x 2]. col1 is startframe, col2 is one-past-endframe
      [sp,ep] = get_interval_ends(obj.hSelIm.CData);
      bouts = [sp(:) ep(:)];
    end
    
    function selectClearSelection(obj)
      obj.selectInit();
    end
    
    function selectClearBout(obj,iBout)
      [sp,ep] = get_interval_ends
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
    function props = getCurProp(obj)
      props = obj.curprop;
    end
    function setCurProp(obj,newprop)
      obj.curprop = newprop;
      obj.setLabelsFull();
    end    
  end
  
  
  %% Private methods
  methods (Access=private) % callbacks
    function cbkBDF(obj,src,evt) %#ok<INUSL>
      if evt.Button==1
        % Navigate to clicked frame
        
        pos = get(obj.hAx,'CurrentPoint');
        frm = round(pos(1,1));
        frm = min(max(frm,1),obj.nfrm);
        obj.lObj.setFrame(frm);
      end
    end
    function cbkLabelMode(obj,src,evt) %#ok<INUSD>
      onoff = onIff(obj.lObj.labelMode==LabelMode.ERRORCORRECT);
      set(obj.hMarked,'Visible',onoff);
    end
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
      iBout = src.UserData.iBout;
      boutsAll = src.Parent.UserData.bouts;
      bout = boutsAll(iBout,:);
      obj.hSelIm.CData(:,bout(1):bout(2)-1) = 0;
    end
  end

  methods (Access=private)
    function lpos = getDataCurrMovTgt(obj)
      % lpos: [nptsxnfrm]
      
      pndx = find(strcmp(obj.props(:,1),obj.curprop));
      ptype = obj.props{pndx,2};
      pcode = obj.props{pndx,3};
      
      switch ptype
        case {'Labels' 'Labels2'}
          iMov = obj.lObj.currMovie;
          iTgt = obj.lObj.currTarget;
          if iMov>0
            if strcmp(ptype,'Labels')
              lObjlpos = obj.lObj.labeledpos{iMov};
            else
              lObjlpos = obj.lObj.labeledpos2{iMov};
            end
            switch pcode
              case 'x'
                lpos = squeeze(lObjlpos(:,1,:,iTgt));
              case 'y'
                lpos = squeeze(lObjlpos(:,2,:,iTgt));
              case 'dx'
                lpos = squeeze(lObjlpos(:,1,:,iTgt));
                lpos = diff(lpos,1,2);
                lpos(:,end+1) = nan;
              case 'dy'
                lpos = squeeze(lObjlpos(:,2,:,iTgt));
                lpos = diff(lpos,1,2);
                lpos(:,end+1) = nan;
              case '|dx|'
                lpos = squeeze(lObjlpos(:,1,:,iTgt));
                lpos = abs(diff(lpos,1,2));
                lpos(:,end+1) = nan;
              case '|dy|'
                lpos = squeeze(lObjlpos(:,2,:,iTgt));
                lpos = abs(diff(lpos,1,2));
                lpos(:,end+1) = nan;
              case 'occluded'
                curd = obj.lObj.labeledpostag{iMov}(:,:,iTgt);
                lpos =  double(strcmp(curd,'occ'));
              otherwise
                warndlg('Unknown property to display');
                lpos = nan(obj.npts,1);
            end
          else
            lpos = nan(obj.npts,1);
          end   
        case 'Tracks'
          lpos = obj.tracker.getPropValues(pcode);
          szassert(lpos,[obj.npts 1]);
      end
    end
    
    function lpos = getMarkedDataCurrMovTgt(obj)
      % lpos: [nptsxnfrm]
      
      iMov = obj.lObj.currMovie;
      if iMov>0
        iTgt = obj.lObj.currTarget;
        lpos = squeeze(obj.lObj.labeledposMarked{iMov}(:,:,iTgt));
      else
        lpos = false(obj.lObj.nLabelPoints,1);
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
