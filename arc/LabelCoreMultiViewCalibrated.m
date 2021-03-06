classdef LabelCoreMultiViewCalibrated < LabelCore & LabelCoreMVMixin

  % Hitting a number key gets you "working on" a certain pt. Other pts
  % dimmed; working pts are highlighted in all views
 
  % Clicking on a working point will do EPL projection on all other
  % views. The working point can be dragged etc. When the working pt is
  % first clicked, it will become colored, with EPLs in other views having 
  % the same color.
  % 
  % At this pt, click-dragging (adjusting) another pt will provide 
  % 3d-reconstructed point spreads in the third/remaining views. 
  % Right-click on either of the first two points to "unadjust" it.
  %
  % When done, hit another number key to change the working point.
  %
  % When done with all points, hit Accept to Accept labels.
  %
  % This requires a 'CalibratedRig' that knows how to compute EPLs and
  % reconstruct 3dpts.
  	
  properties
    supportsMultiView = true;
    supportsCalibration = true;
  end
  
  properties
    iPt2iAx       % [npts]. iPt2iAx(iPt) gives the axis index for iPt
    % .hPts       % [npts] from LabelCore. hLine handles for pts (in
    %               respective axes)
    % .hPtsTxt    % [npts]
    hPtsColors    % [nptsx3] colors for pts, based on prefs.ColorsSets
    hPtsTxtStrs   % [npts] cellstr, text labels for each pt
    iSet2iPt      % [nset x nview]. A point 'set' is a nview-tuple of point 
                  % indices that represent a single physical (3d) point.
                  % .iSet2iPt(iSet,:) are the nview pt indices that
                  % correspond to pointset iSet.
    iPt2iSet      % [npts]. set index for each point.
  end
  properties (Dependent)
    nView         % scalar
    nPointSet     % scalar, number of 'point sets'.    
  end  
    
  %% Projections
  properties
    iSetWorking      % scalar. Set index of working set. Can be nan for no working set.

    pjtIPts          % [1 2] vector; current first/anchor working pt. either
                     % [nan nan], [iPt1 nan], or [iPt1 iPt2]
    pjtHLinesEpi     % [nview]. line handles for epipolar lines
    pjtHLinesRecon   % [nview]. line handles for reconstructed pts
    
    pjtCalRig         % Scalar some-kind-of-calibration object
  end
  properties (Dependent)
    pjtState         % either 0, 1, or 2 for number of defined working pts
  end
  
  %% Misc
  properties
    % click-drag
    iPtMove;     % scalar. Either nan, or index of pt being moved
    tfMoved;     % scalar logical; if true, pt being moved was actually moved
    tfAdjusted;  % nPts x 1 logical vec. If true, pt has been adjusted from template
    tfPtSel;     % nPts x 1 logical vec. If true, pt is currently selected
  end
 
  
  %% dep prop getters
  methods
    function v = get.nView(obj)
      v = obj.labeler.nview;
    end
    function v = get.nPointSet(obj)
      v = size(obj.iSet2iPt,1);
    end
    function v = get.pjtState(obj)
      v = nnz(~isnan(obj.pjtIPts));
    end
  end
    
  %% Ctor/Dtor
  methods
    
    function obj = LabelCoreMultiViewCalibrated(varargin)
      obj = obj@LabelCore(varargin{:});
    end
    
    function delete(obj)
      deleteValidHandles(obj.pjtHLinesEpi);
      obj.pjtHLinesEpi = [];
      deleteValidHandles(obj.pjtHLinesRecon);
      obj.pjtHLinesRecon = [];
    end
    
    function initHook(obj)
      obj.iPt2iAx = obj.labeler.labeledposIPt2View;
      obj.iPt2iSet = obj.labeler.labeledposIPt2Set;
      obj.iSet2iPt = obj.labeler.labeledposIPtSetMap;
      
      % redefine .hPts, .hPtsTxt (originally initted in LabelCore.init())
      deleteValidHandles(obj.hPts);
      deleteValidHandles(obj.hPtsTxt);
      obj.hPts = gobjects(obj.nPts,1);
      obj.hPtsTxt = gobjects(obj.nPts,1);
      ppi = obj.ptsPlotInfo;
      obj.hPtsColors = nan(obj.nPointSet,3);
      obj.hPtsTxtStrs = cell(obj.nPts,1);
      for iPt=1:obj.nPts
        iSet = obj.iPt2iSet(iPt);
        setClr = ppi.ColorsSets(iSet,:);
        obj.hPtsColors(iPt,:) = setClr;
        ptsArgs = {nan,nan,ppi.Marker,...
          'ZData',1,... % AL 20160628: seems to help with making points clickable but who knows
          'MarkerSize',ppi.MarkerSize,...
          'LineWidth',ppi.LineWidth,...
          'Color',setClr,...
          'UserData',iPt,...
          'HitTest','on',...
          'ButtonDownFcn',@(s,e)obj.ptBDF(s,e)};
        ax = obj.hAx(obj.iPt2iAx(iPt));
        obj.hPts(iPt) = plot(ax,ptsArgs{:});
        txtStr = num2str(iSet);
        obj.hPtsTxt(iPt) = text(nan,nan,txtStr,...
          'Parent',ax,...
          'Color',setClr,...
          'FontSize',ppi.FontSize,...
          'Hittest','off');
        obj.hPtsTxtStrs{iPt} = txtStr;
      end
      
      obj.setRandomTemplate();
           
      obj.tfAdjusted = false(obj.nPts,1);
      obj.tfPtSel = false(obj.nPts,1);       

      obj.txLblCoreAux.Visible = 'on';      
     
      obj.projectionWorkingSetClear();
      obj.projectionInit();
      
      initHook@LabelCoreMVMixin(obj);
    end
    
  end
  
  %% LabelCore overloads
  methods

    % newFrameAndTarget() combines all the brains of transitions for 
    % convenience reasons
    
    function newFrame(obj,iFrm0,iFrm1,iTgt)
      obj.newFrameAndTarget(iFrm0,iFrm1,iTgt,iTgt);
    end
    
    function newTarget(obj,iTgt0,iTgt1,iFrm)
      obj.newFrameAndTarget(iFrm,iFrm,iTgt0,iTgt1);
    end
    
    function newFrameAndTarget(obj,iFrm0,iFrm1,iTgt0,iTgt1)
      %#CALOK
      [tflabeled,lpos,lpostag] = obj.labeler.labelPosIsLabeled(iFrm1,iTgt1);
      if tflabeled
        obj.assignLabelCoords(lpos,'lblTags',lpostag);
        obj.enterAccepted(false);
      else
        assert(iTgt0==iTgt1,'Multiple targets unsupported.');
        assert(~obj.labeler.hasTrx,'Targets are unsupported.');
        obj.enterAdjust(true,false);
      end
      
      % working set: unchanged
      
      % projection state: very crude refresh
      obj.projectionRefresh();
    end
    
    function clearLabels(obj)
      %#CALOK
      obj.enterAdjust(true,true);
      obj.projectionWorkingSetClear();
      obj.projectionClear();
    end
    
    function acceptLabels(obj)
      obj.enterAccepted(true);
    end
    
    function unAcceptLabels(obj)
      obj.enterAdjust(false,false);
    end 
    
    function axBDF(obj,src,evt) %#ok<INUSD>
      [tf,iSel] = obj.selAnyPointSelected();
      if tf
        iAx = obj.iPt2iAx(iSel);
        ax = obj.hAx(iAx);        
        pos = get(ax,'CurrentPoint');
        pos = pos(1,1:2);
        obj.assignLabelCoordsIRaw(pos,iSel);
        obj.setPointAdjusted(iSel);
        obj.selToggleSelectPoint(iSel);
        if obj.tfOcc(iSel)
          % AL should be unnec branch
          obj.tfOcc(iSel) = false;
          obj.refreshOccludedPts();
        end
        % estOcc status unchanged
        switch obj.state
          case LabelState.ADJUST
            % none
          case LabelState.ACCEPTED
            obj.enterAdjust(false,false);
        end
        obj.projectionRefresh();
      end     
    end
    
    function ptBDF(obj,src,evt)
      %#CALOK
      iPt = src.UserData;
      switch evt.Button
        case 1
          obj.iPtMove = iPt;
          obj.tfMoved = false;
        case 3
          obj.toggleEstOccPoint(iPt);
      end
    end
    
    function wbmf(obj,src,evt) %#ok<INUSD>
      %#CALOK
      
      iPt = obj.iPtMove;
      if ~isnan(iPt)
        if obj.state==LabelState.ACCEPTED
          obj.enterAdjust(false,false);
        end

        iAx = obj.iPt2iAx(iPt);
        ax = obj.hAx(iAx);
        tmp = get(ax,'CurrentPoint');
        pos = tmp(1,1:2);
        obj.tfMoved = true;
        obj.assignLabelCoordsIRaw(pos,iPt);
        obj.setPointAdjusted(iPt);
        
        obj.projectionRefresh();
      end
    end
    
    function wbuf(obj,src,evt) %#ok<INUSD>
      %#CALOK
      
      iPt = obj.iPtMove;
      if ~isnan(iPt)
        if obj.tfMoved
          % none
        else
          % point was clicked but not moved
          obj.projectToggleState(iPt);
        end
      end
      obj.iPtMove = nan;
      obj.tfMoved = false;
    end
    
    function tfKPused = kpf(obj,src,evt) %#ok<INUSL>
      %#CALOK
      key = evt.Key;
      modifier = evt.Modifier;      
      tfCtrl = any(strcmp('control',modifier));
      tfShft = any(strcmp('shift',modifier));
      
      tfKPused = true;
      if strcmp(key,'h') && tfCtrl
        obj.labelsHideToggle();
      elseif strcmp(key,'space')
        [tfSel,iSel] = obj.selAnyPointSelected();
        if tfSel && ~obj.tfOcc(iSel) % Second cond should be unnec
          obj.projectToggleState(iSel);
        end
      elseif strcmp(key,'s') && ~tfCtrl
        if obj.state==LabelState.ADJUST
          obj.acceptLabels();
        end
      elseif any(strcmp(key,{'d' 'equal'}))
        obj.labeler.frameUp(tfCtrl);
      elseif any(strcmp(key,{'a' 'hyphen'}))
        obj.labeler.frameDown(tfCtrl);
      elseif strcmp(key,'o') && ~tfCtrl
        [tfSel,iSel] = obj.selAnyPointSelected();
        if tfSel
          obj.toggleEstOccPoint(iSel);
        end
      elseif any(strcmp(key,{'leftarrow' 'rightarrow' 'uparrow' 'downarrow'}))
        [tfSel,iSel] = obj.selAnyPointSelected();
        if tfSel && ~obj.tfOcc(iSel)
          tfShift = any(strcmp('shift',modifier));
          xy = obj.getLabelCoordsI(iSel);
          iAx = obj.iPt2iAx(iSel);
          ax = obj.hAx(iAx);
          switch key
            case 'leftarrow'
              xl = xlim(ax);
              dx = diff(xl);
              if tfShift
                xy(1) = xy(1) - dx/obj.DXFACBIG;
              else
                xy(1) = xy(1) - dx/obj.DXFAC;
              end
              xy(1) = max(xy(1),1);
            case 'rightarrow'
              xl = xlim(ax);
              dx = diff(xl);
              if tfShift
                xy(1) = xy(1) + dx/obj.DXFACBIG;
              else
                xy(1) = xy(1) + dx/obj.DXFAC;
              end
              ncs = obj.labeler.movienc;
              xy(1) = min(xy(1),ncs(iAx));
            case 'uparrow'
              yl = ylim(ax);
              dy = diff(yl);
              if tfShift
                xy(2) = xy(2) - dy/obj.DXFACBIG;
              else
                xy(2) = xy(2) - dy/obj.DXFAC;
              end
              xy(2) = max(xy(2),1);
            case 'downarrow'
              yl = ylim(ax);
              dy = diff(yl);
              if tfShift
                xy(2) = xy(2) + dy/obj.DXFACBIG;
              else
                xy(2) = xy(2) + dy/obj.DXFAC;
              end
              nrs = obj.labeler.movienr;
              xy(2) = min(xy(2),nrs(iAx));
          end
          obj.assignLabelCoordsIRaw(xy,iSel);
          switch obj.state
            case LabelState.ADJUST
              obj.setPointAdjusted(iSel);
            case LabelState.ACCEPTED
              obj.enterAdjust(false,false);
          end
          obj.projectionRefresh();
        elseif strcmp(key,'leftarrow')
          if tfShft
            obj.labeler.frameUpNextLbled(true);
          else
            obj.labeler.frameDown(tfCtrl);
          end
        elseif strcmp(key,'rightarrow')
          if tfShft
            obj.labeler.frameUpNextLbled(false);
          else
            obj.labeler.frameUp(tfCtrl);
          end
        else
          tfKPused = false;
        end
      elseif strcmp(key,'backquote')
        if tfShft
          obj.decrementHotKeySet();
        else
          obj.incrementHotKeySet();
        end
      elseif any(strcmp(key,{'0' '1' '2' '3' '4' '5' '6' '7' '8' '9'}))
        iPt = str2double(key);
        if iPt==0
          iPt = 10;
        end
        [tf,iPt] = obj.numHotKeyInRange(iPt);
        if tf
          obj.selClearSelected(iPt);
          obj.selToggleSelectPoint(iPt);
        end
      else
        tfKPused = false;
      end
    end
    
    function axOccBDF(obj,src,evt) %#ok<INUSD>
      assert(false,'Unsupported for multiview labeling');     
    end

    function h = getLabelingHelp(obj) %#ok<MANU>
      h = { ...
        '* A/D, LEFT/RIGHT, or MINUS(-)/EQUAL(=) decrements/increments the frame shown.'
        '* <ctrl>+A/D, LEFT/RIGHT etc decrement/increment by 10 frames.'
        '* S accepts the labels for the current frame/target.'        
        '* (The letter) O toggles occluded-estimated status.'
        '* 0..9 selects/unselects a point. When a point is selected:'
        '*   LEFT/RIGHT/UP/DOWN adjusts the point.'
        '*   Shift-LEFT, etc adjusts the point by larger steps.' 
        '*   Clicking on the image moves the selected point to that location.'
        '*   <space> projects epipolar lines or 3d-reconstructed points for the current point.'
        '* backquote (`) increments the mapping of the 0-9 hotkeys; shift-backquote decrements.'};
    end
    
    function refreshEstOccPts(obj,varargin)
      % React to an updated .tfEstOcc.
      %
      % optional PVs
      % iPts. Defaults to 1:obj.nPts.
      
      %#MVOK
      
      iPts = myparse(varargin,'iPts',1:obj.nPts);
      obj.refreshPtMarkers(iPts);
    end
        
  end
  
  %% Template
  methods
        
    function setRandomTemplate(obj)
      %# CALOK
      
      lbler = obj.labeler;
      mrs = lbler.movieReader;
      movszs = [[mrs.nr]' [mrs.nc]']; % [nview x 2]. col1: nr. col2: nc
      
      xy = nan(obj.nPts,2);
      for iPt=1:obj.nPts
        iAx = obj.iPt2iAx(iPt);
        nr = movszs(iAx,1);
        nc = movszs(iAx,2);
        xy(iPt,1) = nc/2 + nc/3*2*(rand-0.5);
        xy(iPt,2) = nr/2 + nr/3*2*(rand-0.5);
      end
      obj.assignLabelCoords(xy,'tfClip',false);        
    end
    
  end
  
  %% Projection
  methods
    
    function projectionWorkingSetClear(obj)
      h = obj.hPtsTxt;
      hClrs = obj.hPtsColors;
      for i=1:obj.nPts
        set(h(i),'Color',hClrs(i,:),'FontWeight','normal','EdgeColor','none');
      end
      obj.iSetWorking = nan;
    end
    
    function projectionWorkingSetSet(obj,iSet)
      iPtsSet = obj.iSet2iPt(iSet,:);

      h = obj.hPtsTxt;
      hClrs = obj.hPtsColors;
      for i=1:obj.nPts
        if any(i==iPtsSet)
          set(h(i),'Color',hClrs(i,:),'FontWeight','bold','EdgeColor','w');
        else
          set(h(i),'Color',hClrs(i,:)*.75,'FontWeight','normal','EdgeColor','none');
        end
      end
      obj.iSetWorking = iSet;
    end
    
    function projectionWorkingSetToggle(obj,iSet)
      if isnan(obj.iSetWorking)
        obj.projectionWorkingSetSet(iSet);
      else
        tfMatch = obj.iSetWorking==iSet;
        obj.projectionWorkingSetClear();
        if ~tfMatch
          obj.projectionWorkingSetSet(iSet);
        end
      end
    end
    
    function tf = projectionWorkingSetPointInWS(obj,iPt)
      % Returns true if iPt is in current working set.
      tf = obj.iPt2iSet(iPt)==obj.iSetWorking;
    end
    
    function projectionInit(obj)
      obj.pjtIPts = [nan nan];
      hLEpi = gobjects(1,obj.nView);
      hLRcn = gobjects(1,obj.nView);
      ppimvcm = obj.ptsPlotInfo.MultiViewCalibratedMode;
      gdata = obj.labeler.gdata;
      for iV = 1:obj.nView
        ax = gdata.axes_all(iV);        
        hLEpi(iV) = plot(ax,nan,nan,'-',...
          'LineWidth',ppimvcm.EpipolarLineWidth,'hittest','off');
        hLRcn(iV) = plot(ax,nan,nan,ppimvcm.ReconstructedMarker,...
          'MarkerSize',ppimvcm.ReconstructedMarkerSize,...
          'LineWidth',ppimvcm.ReconstructedLineWidth,...
          'hittest','off');
      end
      obj.pjtHLinesEpi = hLEpi;
      obj.pjtHLinesRecon = hLRcn;
    end
    
    function projectionClear(obj)
      % Clear all projection points.
      
      %# CALOK
      
      for iPt=1:obj.nPts
        set(obj.hPtsTxt(iPt),'String',obj.hPtsTxtStrs{iPt});
      end
      
      obj.pjtIPts = [nan nan];
      set(obj.pjtHLinesEpi,'Visible','off');
      set(obj.pjtHLinesRecon,'Visible','off');
      obj.projectionWorkingSetClear();
    end
    
    function projectToggleState(obj,iPt)
      % Toggle projection status of point iPt. 
      
      %#CALOK
      
      switch obj.pjtState
        case 0
          obj.projectionSetAnchor(iPt);
        case 1
          if iPt==obj.pjtIPts(1)
            obj.projectionClear();
          elseif obj.projectionWorkingSetPointInWS(iPt)
            obj.projectionSet2nd(iPt);
          else
            % iPt is neither anchor pt nor in anchor pt's working set
            obj.projectionClear();
            obj.projectionSetAnchor(iPt);
          end
        case 2
          tf = iPt==obj.pjtIPts;          
          if any(tf)
            idx = find(tf);
            idxOther = mod(idx,2)+1;
            iPtOther = obj.pjtIPts(idxOther);
            obj.projectionClear();
            obj.projectionSetAnchor(iPtOther);            
          else
            obj.projectionClear();
            obj.projectionSetAnchor(iPt);
          end
      end
    end

    function projectionSetAnchor(obj,iPt1)
      %# CALOK
            
      if ~isnan(obj.pjtIPts(1))
        obj.projectionClear();
      end
      hPt1 = obj.hPtsTxt(iPt1);
      set(hPt1,'String',[obj.hPtsTxtStrs{iPt1} 'a']);
      obj.pjtIPts(1) = iPt1;
      assert(isnan(obj.pjtIPts(2)));
      iSet1 = obj.iPt2iSet(iPt1);
      obj.projectionWorkingSetSet(iSet1);
      obj.projectionRefreshEPlines();
    end
    
    function projectionRefreshEPlines(obj)
      % update EPlines based on .pjtIPt1 and coords of that hPt.
      
      assert(obj.pjtState==1);
      
      iPt1 = obj.pjtIPts(1);
      hPt1 = obj.hPts(iPt1);
      xy1 = [hPt1.XData hPt1.YData];
      iAx1 = obj.iPt2iAx(iPt1);
      iAxOther = setdiff(1:obj.nView,iAx1);
      crig = obj.pjtCalRig;
      for iAx = iAxOther
        [x,y] = crig.computeEpiPolarLine(iAx1,xy1,iAx);
        hEpi = obj.pjtHLinesEpi(iAx);
        set(hEpi,'XData',x,'YData',y,'Visible','on','Color',hPt1.Color);
      end
      set(obj.pjtHLinesEpi(iAx1),'Visible','off');
    end
    
    function projectionSet2nd(obj,iPt2)
      %# CALOK
    
      assert(~isnan(obj.pjtIPts(1)));
      assert(isnan(obj.pjtIPts(2)));
      assert(iPt2~=obj.pjtIPts(1),'Second projection point must differ from anchor point.');
      obj.pjtIPts(2) = iPt2;
      set(obj.pjtHLinesEpi,'Visible','off');
      
      set(obj.hPtsTxt(iPt2),'String',[obj.hPtsTxtStrs{iPt2} 'a']);
      
      obj.projectionRefreshReconPts();
    end
    
    function projectionRefreshReconPts(obj)
      % update recon pts based on .pjtIPt1 and .pjtIPt2 and coords of 
      % corresponding hPts.
      
      assert(obj.pjtState==2);
      
      iPt1 = obj.pjtIPts(1);
      iPt2 = obj.pjtIPts(2);
      iAx1 = obj.iPt2iAx(iPt1);
      iAx2 = obj.iPt2iAx(iPt2);
      hPt1 = obj.hPts(iPt1);
      hPt2 = obj.hPts(iPt2);
      
      xy1 = [hPt1.XData hPt1.YData];
      xy2 = [hPt2.XData hPt2.YData];
      iAxOther = setdiff(1:obj.nView,[iAx1 iAx2]);
      crig = obj.pjtCalRig;
      for iAx = iAxOther
        [x,y] = crig.reconstruct(iAx1,xy1,iAx2,xy2,iAx);
        set(obj.pjtHLinesRecon(iAx),...
          'XData',x,'YData',y,...
          'Visible','on','Color',hPt1.Color);
      end
    end
    
    function projectionRefresh(obj)
      switch obj.pjtState
        case 0
          % none
        case 1
          obj.projectionRefreshEPlines();
        case 2
          obj.projectionRefreshReconPts();
        otherwise
          assert(false);
      end
    end
    
    function projectionSetCalRig(obj,crig)
      assert(isa(crig,'CalRig'));
      
      crigViewSzs = crig.viewSizes; % [nView x 2]; each row is [nc nr]
      lObj = obj.labeler;
      imsAll = lObj.gdata.images_all;
      for iView = 1:obj.nView
        cdata = imsAll(iView).CData;
        imnr = size(cdata,1);
        imnc = size(cdata,2);
        crignc = crigViewSzs(iView,1);
        crignr = crigViewSzs(iView,2);
        if imnr~=crignr || imnc~=crignc
          warning('LabelCoreMultiViewCalibrated:projectionSetCalRig',...
            'View %d (%s): image size is [nr nc]=[%d %d]; calibration based on [%d %d]',...
            iView,crig.viewNames{iView},...
            imnr,imnc,crignr,crignc);
        end
      end
      
      obj.pjtCalRig = crig;
    end
    
  end
  
  %% Selected
  methods 
    
    function [tf,iSelected] = selAnyPointSelected(obj)
      tf = any(obj.tfPtSel);
      iSelected = find(obj.tfPtSel,1);
    end
     
    function selClearSelected(obj,iExclude)
      tf = obj.tfPtSel;
      if exist('iExclude','var')>0
        tf(iExclude) = false;
      end
      iSel = find(tf);
      for i = iSel(:)'
        obj.selToggleSelectPoint(i);
      end
    end
    
    function selToggleSelectPoint(obj,iPt)
      tfSel = ~obj.tfPtSel(iPt);
      obj.tfPtSel(:) = false;
      obj.tfPtSel(iPt) = tfSel;
      
      obj.refreshPtMarkers(iPt);
      % Also update hPtsOcc markers
      if tfSel
        mrkr = obj.ptsPlotInfo.TemplateMode.SelectedPointMarker;
      else
        mrkr = obj.ptsPlotInfo.Marker;
      end
      set(obj.hPtsOcc(iPt),'Marker',mrkr);
    end

  end
  
  %% 
  methods
    
    % ADJUST/ACCEPTED-NESS
    % What is the "Adjust" state?
    % - The button says "Accept" => Either
    % - 1) The current frame has no recorded labels (all pts shown as
    %       white) OR
    % - 2) The current frame HAS recorded labels (pts shown in color), but 
    %       they differ from the points as currently shown 
    %
    % Meanwhile, in the "Accept" state:
    % - The Button says "Accepted" =>
    % - 1) What you see is what is recorded in the Labeler (pts shown in
    %   color)
    %
    % WORKING SET
    % - When a pointset is working, then all its points are shown in full
    % alpha while others are faded.
    % - You can have no working pointsets.
    %
    % PROJECTION POINTS
    % - You can click on working pts to set them as projection pts. First
    % pt => anchor. This changes the marker to a square and creates EPLs in
    % the other views.
    % - Second pt => 2nd pt. This changes the marker and creates
    % 3dprojspreads in remaining views.
    % - Regardless of projection-ness you can click-drag any points in the
    % working set around.
    % - Single-click to release/remove a pt from anchor-ness or 2nd-ness
    % - Regardless of projection state, you can Accept, which writes
    % current positions to Labeler.
    
    function enterAdjust(obj,tfResetPts,tfClearLabeledPos)
      % Enter adjustment state for current frame/tgt.
      %
      % if tfReset, reset all points to pre-adjustment (white).
      % if tfClearLabeledPos, clear labeled pos.

      %#CALOK
      
      if tfResetPts
        tpClr = obj.ptsPlotInfo.TemplateMode.TemplatePointColor;
        arrayfun(@(x)set(x,'Color',tpClr),obj.hPts);
        obj.tfAdjusted(:) = false;
      end
      if tfClearLabeledPos
        obj.labeler.labelPosClear();
      end
        
      obj.iPtMove = nan;
      obj.tfMoved = false;
      
      set(obj.tbAccept,'BackgroundColor',[0.6,0,0],'String','Accept',...
        'Value',0,'Enable','on');
      obj.state = LabelState.ADJUST;
    end
        
    function enterAccepted(obj,tfSetLabelPos)
      % Enter accepted state for current frame/tgt. All points colored. If
      % tfSetLabelPos, all points/tags written to labelpos/labelpostag.
      
      %#CALOK
            
      nPts = obj.nPts;
      ptsH = obj.hPts;
      clrs = obj.ptsPlotInfo.Colors;
      for i = 1:nPts
        set(ptsH(i),'Color',clrs(i,:));
        set(obj.hPtsOcc(i),'Color',clrs(i,:));
      end
      
      obj.tfAdjusted(:) = true;
      
      if tfSetLabelPos
        xy = obj.getLabelCoords();
        obj.labeler.labelPosSet(xy);
        obj.setLabelPosTagFromEstOcc();
      end
      set(obj.tbAccept,'BackgroundColor',[0,0.4,0],'String','Accepted',...
        'Value',1,'Enable','on');
      obj.state = LabelState.ACCEPTED;
    end
    
    function setPointAdjusted(obj,iSel)
      %#CALOK
      if ~obj.tfAdjusted(iSel)
        obj.tfAdjusted(iSel) = true;
        clr = obj.hPtsColors(iSel,:);
        set(obj.hPts(iSel),'Color',clr);
        %set(obj.hPtsOcc(iSel),'Color',clr);
      end
    end
    
    function toggleEstOccPoint(obj,iPt)
      obj.tfEstOcc(iPt) = ~obj.tfEstOcc(iPt);
      obj.refreshEstOccPts('iPts',iPt);
      if obj.state==LabelState.ACCEPTED
        obj.enterAdjust(false,false);
      end
    end
    
    function refreshPtMarkers(obj,iPts)
      % Update obj.hPts Markers based on .tfEstOcc and .tfPtSel.
      
      ppi = obj.ptsPlotInfo;
      ppitm = ppi.TemplateMode;

      hPoints = obj.hPts(iPts);
      tfSel = obj.tfPtSel(iPts);
      tfEO = obj.tfEstOcc(iPts);
      
      set(hPoints(tfSel & tfEO),'Marker',ppitm.SelectedOccludedMarker); % historical quirk, use props instead of ppi; fix this at some pt
      set(hPoints(tfSel & ~tfEO),'Marker',ppitm.SelectedPointMarker);
      set(hPoints(~tfSel & tfEO),'Marker',ppi.OccludedMarker);
      set(hPoints(~tfSel & ~tfEO),'Marker',ppi.Marker);
    end
            
  end
    
end