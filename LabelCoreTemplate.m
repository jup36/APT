classdef LabelCoreTemplate < LabelCore
% Template-based labeling  
  
  % DESCRIPTION
  % In Template mode, there is a set of template/"white" points on the
  % image at all times. (When starting, these points need to be either
  % specified or loaded/imported.) To label a frame, adjust the points as 
  % necessary and accept. Adjusted points are shown in colors (rather than
  % white).
  %
  % Points may also be Selected using hotkeys (0..9). When a point is
  % selected, the arrow-keys adjust the point as if by mouse. Mouse-clicks
  % on the image also jump the point immediately to that location.
  % Adjustment of a point in this way is identical in concept to
  % click-dragging.
  %
  % To mark a point as FullyOccluded, select it with a hotkey and click in 
  % the occluded box. To un-occlude, select it with a hotkey and click in 
  % the main image.
  %
  % To toggle a point as EstimatedOccluded, right-click on the point, or
  % use the 'o' hotkey.
  %
  %
  % IMPL NOTES
  % 2 basic states, Adjusting and Accepted
  % - Adjusting, unlabeled frame underneath
  % -- 'untouched' template points are white
  % -- 'touched' template points are colored
  % -- Accept writes to labeledpos
  % - Adjusting, labeled frame underneath
  % -- all pts colored/'touched'
  % -- labeledpos exists underneath and is not overwritten until Acceptance
  % - Accepted
  % -- all points colored.
  % -- Can go back into adjustment mode, but all points turn white as if from template.
  %
  % TRANSITIONS W/OUT TRX
  % Note: Once a template is created/loaded, there is a set of points (either
  %  all white/template, or partially template, or all colored) on the image
  %  at all times.
  % - New unlabeled frame
  % -- Label point positions are unchanged, but all points become white.
  %    If scrolling forward, the template from frame-1 will be used etc.
  % -- (Enhancement? not implemented) Accepted points from 'nearest'
  %    neighboring labeled frame (eg frm-1, or <frmLastVisited>, become
  %    white points in new frame
  % - New labeled frame
  % -- Previously accepted labels shown as colored points.
  %
  % TRANSITIONS W/TRX
  % - New unlabeled frame (current target)
  % -- Existing points are auto-aligned onto new frame. The existing
  %    points could represent previously accepted labels, or just the
  %    previous template state.
  % - New labeled frame (current target)
  % -- Previously accepted labels shown as colored points.
  % - New target (same frame), unlabeled
  % -- Last labeled frame for new target acts as template; points auto-aligned.
  % -- If no previously labeled frame for this target, current white points are aligned onto new target.
  % - New target (same frame), labeled
  % -- Previously accepted labels shown as colored points.
  
  % STATE + COSMETICS (besides the coordinates)
  %
  % Adjustedness. 
  % Conceptually, unadjusted points have not been touched by a person. They 
  % are either template-guesses (white) or template-from-tracking-
  % predictions (colored, but with different markersize/linewidth). 
  % Existing labels, or points that have been moved have been adjusted. 
  % Currently, as an implementation edge case, toggling selectedness (see 
  % next) or estocc-ness (see next) does not affect adjustness although 
  % arguably these actions should set adjustedness.
  %
  % Adjustedness is stored in .tfAdjusted and should be mutated only with
  % the adjusted* api. Adjustedness is indicated in the UI via hPt color, 
  % linewidth, markersize and hPtTxt FontAngle.
  %
  % Selectedness.
  % A selected point is one that is currently being "worked on". This gives
  % the point "focus" and enables eg using arrow keys for adjustment. Only 
  % one point can be selected at a time. 
  %
  % Selectedness is stored in .tfSel and should be mutated only through the
  % LabelCore/selected* api. Selectedness is indicated in the UI via hPt
  % markers; use refreshPtMarkers() to update the UI.
  %
  % Estimated-occluded-ness.
  % An estimated-occluded point is one whose position is uncertain to some
  % degree due to occlusions in the image. 
  %
  % Estimated-occ-ness is stored in .tfEstOcc and should be mutated only
  % through toggleEstOcc. Est-occ-ness is indicated in the UI via hPt
  % markers, and again refreshPtMarkers() is the universal update.

  properties
    supportsMultiView = false;
    supportsCalibration = false;
  end
  
  properties
    iPtMove;     % scalar. Either nan, or index of pt being moved
    tfMoved;     % scalar logical; if true, pt being moved was actually moved
    
    tfAdjusted;  % nPts x 1 logical vec. If true, pt has been adjusted from 
                 % template or tracking prediction
    
    kpfIPtFor1Key;  % scalar positive integer. This is the point index that 
                 % the '1' hotkey maps to, eg typically this will take the 
                 % values 1, 11, 21, ...
                 
    hPtsPVRegAdjustedness; % HG PV-pairs for normal marker size, linewidth
    hPtsPVPredAdjustedness; % " for unadjusted tracking predictions
  end  
  
  methods
    
    function set.kpfIPtFor1Key(obj,val)
      obj.kpfIPtFor1Key = val;
      obj.refreshTxLabelCoreAux();
    end
    
  end
  
  methods
    
    function obj = LabelCoreTemplate(varargin)
      obj = obj@LabelCore(varargin{:});
    end
    
    function initHook(obj)
      obj.setRandomTemplate();
            
      npts = obj.nPts;
      obj.tfAdjusted = false(npts,1);
      
      ppi = obj.ptsPlotInfo;
      obj.hPtsPVRegAdjustedness = struct( ...
        'MarkerSize',ppi.MarkerSize,...
        'LineWidth',ppi.LineWidth);
      obj.hPtsPVPredAdjustedness = struct( ...
        'MarkerSize',ppi.MarkerSize*1.5,...
        'LineWidth',ppi.LineWidth/2);
      
      obj.txLblCoreAux.Visible = 'on';
      obj.kpfIPtFor1Key = 1;
      obj.refreshTxLabelCoreAux();

      % LabelCore should prob not talk directly to tracker
      tObj = obj.labeler.tracker;
      if ~isempty(tObj) && ~tObj.hideViz
        warningNoTrace('LabelCoreTemplate:viz',...
          'Enabling View>Hide Predictions. Tracking predictions (when present) are now shown as template points in Template Mode.');
        tObj.setHideViz(true);
      end
    end
    
  end
  
  methods

    % For LabelCoreTemplate, newFrameAndTarget() combines all the brains of
    % transitions for convenience reasons
    
    function newFrame(obj,iFrm0,iFrm1,iTgt)
      obj.newFrameAndTarget(iFrm0,iFrm1,iTgt,iTgt);
    end
    
    function newTarget(obj,iTgt0,iTgt1,iFrm)
      obj.newFrameAndTarget(iFrm,iFrm,iTgt0,iTgt1);
    end
    
    function newFrameAndTarget(obj,iFrm0,iFrm1,iTgt0,iTgt1)
      lObj = obj.labeler;
      
      [tflabeled,lpos,lpostag] = lObj.labelPosIsLabeled(iFrm1,iTgt1);
      if tflabeled
        obj.assignLabelCoords(lpos,'lblTags',lpostag);
        obj.enterAccepted(false);
        return;
      end
      
      assert(iFrm1==lObj.currFrame);
      [tftrked,lposTrk] = lObj.trackIsCurrMovFrmTracked(iTgt1);
      if tftrked
        obj.assignLabelCoords(lposTrk);
        obj.enterAdjust(LabelCoreTemplateResetType.RESETPREDICTED,false);
        return;
      end
      
      if iTgt0==iTgt1 % same target, new frame
        if lObj.hasTrx
          % existing points are aligned onto new frame based on trx at
          % (currTarget,prevFrame) and (currTarget,currFrame)
          
          xy0 = obj.getLabelCoords();
          xy = LabelCore.transformPtsTrx(xy0,...
            lObj.trx(iTgt0),iFrm0,...
            lObj.trx(iTgt0),iFrm1);
          obj.assignLabelCoords(xy,'tfClip',true);
        else
          % none, leave pts as-is
        end
      else % different target
        assert(lObj.hasTrx,'Must have trx to change targets.');
        [tfneighbor,iFrm0Neighb,lpos0] = ...
          lObj.labelPosLabeledNeighbor(iFrm1,iTgt1);
        if tfneighbor
          xy = LabelCore.transformPtsTrx(lpos0,...
            lObj.trx(iTgt1),iFrm0Neighb,...
            lObj.trx(iTgt1),iFrm1);
        else
          % no neighboring previously labeled points for new target.
          % Just start with current points for previous target/frame.
          xy0 = obj.getLabelCoords();
          xy = LabelCore.transformPtsTrx(xy0,...
            lObj.trx(iTgt0),iFrm0,...
            lObj.trx(iTgt1),iFrm1);
        end
        obj.assignLabelCoords(xy,'tfClip',true);
      end
      obj.enterAdjust(LabelCoreTemplateResetType.RESET,false);
    end
    
    function clearLabels(obj)
      obj.clearSelected();
      obj.enterAdjust(LabelCoreTemplateResetType.RESET,true);
    end
    
    function acceptLabels(obj)
      obj.enterAccepted(true);
    end
    
    function unAcceptLabels(obj)
      obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
    end 
    
    function axBDF(obj,src,evt) %#ok<INUSD>
      [tf,iSel] = obj.anyPointSelected();
      if tf
        pos = get(obj.hAx,'CurrentPoint');
        pos = pos(1,1:2);
        obj.assignLabelCoordsIRaw(pos,iSel);
        obj.setPointAdjusted(iSel);
        obj.toggleSelectPoint(iSel);
        if obj.tfOcc(iSel)
          obj.tfOcc(iSel) = false;
          obj.refreshOccludedPts();
        end
        % estOcc status unchanged
        switch obj.state
          case LabelState.ADJUST
            % none
          case LabelState.ACCEPTED
            obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
        end
      end     
    end
    
    function ptBDF(obj,src,evt)
      switch evt.Button
        case 1
          tf = obj.anyPointSelected();
          if tf
            % none
          else
            % prepare for click-drag of pt
            
            if obj.state==LabelState.ACCEPTED
              obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
            end
            iPt = get(src,'UserData');
            obj.iPtMove = iPt;
            obj.tfMoved = false;
          end
        case 3
          iPt = get(src,'UserData');
          obj.toggleEstOccPoint(iPt);
      end
    end
    
    function wbmf(obj,src,evt) %#ok<INUSD>
      if obj.state==LabelState.ADJUST
        iPt = obj.iPtMove;
        if ~isnan(iPt)
          ax = obj.hAx;
          tmp = get(ax,'CurrentPoint');
          pos = tmp(1,1:2);
          obj.tfMoved = true;
          obj.assignLabelCoordsIRaw(pos,iPt);
          obj.setPointAdjusted(iPt);
        end
      end
    end
    
    function wbuf(obj,src,evt) %#ok<INUSD>
      if obj.state==LabelState.ADJUST
        iPt = obj.iPtMove;
        if ~isnan(iPt) && ~obj.tfMoved
          % point was clicked but not moved
          obj.clearSelected(iPt);
          obj.toggleSelectPoint(iPt);
        end
        
        obj.iPtMove = nan;
        obj.tfMoved = false;
      end
    end
    
    function tfKPused = kpf(obj,src,evt)
      key = evt.Key;
      modifier = evt.Modifier;
      tfCtrl = any(strcmp('control',modifier));
      tfShft = any(strcmp('shift',modifier));
      
      tfKPused = true;
      lObj = obj.labeler;
      
      % Hack iss#58. Ensure focus is not on slider_frame. In practice this
      % callback is called before slider_frame_Callback when slider_frame
      % has focus.
      txStatus = lObj.gdata.txStatus;
      if src~=txStatus % protect against repeated kpfs (eg scrolling vid)
        uicontrol(lObj.gdata.txStatus);
      end

      if any(strcmp(key,{'s' 'space'})) && ~tfCtrl
        if obj.state==LabelState.ADJUST
          obj.acceptLabels();
        end
      elseif any(strcmp(key,{'d' 'equal'}))
        lObj.frameUp(tfCtrl);
      elseif any(strcmp(key,{'a' 'hyphen'}))
        lObj.frameDown(tfCtrl);
      elseif strcmp(key,'o') && ~tfCtrl
        [tfSel,iSel] = obj.anyPointSelected();
        if tfSel
          obj.toggleEstOccPoint(iSel);
        end
      elseif any(strcmp(key,{'leftarrow' 'rightarrow' 'uparrow' 'downarrow'}))
        [tfSel,iSel] = obj.anyPointSelected();
        if tfSel && ~obj.tfOcc(iSel)
          tfShift = any(strcmp('shift',modifier));
          xy = obj.getLabelCoordsI(iSel);
          switch key
            case 'leftarrow'
              dxdy = -lObj.videoCurrentRightVec();
            case 'rightarrow'
              dxdy = lObj.videoCurrentRightVec();
            case 'uparrow'
              dxdy = lObj.videoCurrentUpVec();
            case 'downarrow'
              dxdy = -lObj.videoCurrentUpVec();
          end
          if tfShift
            xy = xy + dxdy*10;
          else
            xy = xy + dxdy;
          end
          xy = lObj.videoClipToVideo(xy);
          obj.assignLabelCoordsIRaw(xy,iSel);
          switch obj.state
            case LabelState.ADJUST
              obj.setPointAdjusted(iSel);
            case LabelState.ACCEPTED
              obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
          end
        else
          tfKPused = false;
        end
      elseif strcmp(key,'backquote')
        iPt = obj.kpfIPtFor1Key+10;
        if iPt > obj.nPts
          iPt = 1;
        end
        obj.kpfIPtFor1Key = iPt;
      elseif any(strcmp(key,{'0' '1' '2' '3' '4' '5' '6' '7' '8' '9'}))
        iPt = str2double(key);
        if iPt==0
          iPt = 10;
        end
        iPt = iPt+obj.kpfIPtFor1Key-1;
        if iPt > obj.nPts
          return;
        end
        obj.clearSelected(iPt);
        obj.toggleSelectPoint(iPt);
      else
        tfKPused = false;
      end
    end
    
    function axOccBDF(obj,src,evt) %#ok<INUSD>
      [tf,iSel] = obj.anyPointSelected();
      if tf
        obj.setPointAdjusted(iSel);
        obj.toggleSelectPoint(iSel);
        obj.tfOcc(iSel) = true;
        obj.tfEstOcc(iSel) = false;
        obj.refreshOccludedPts();
        obj.refreshPtMarkers('iPts',iSel);
        switch obj.state
          case LabelState.ADJUST
            % none
          case LabelState.ACCEPTED
            obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
        end
      end   
    end

    function h = getLabelingHelp(obj) %#ok<MANU>
      h = { ...
        '* A/D, LEFT/RIGHT, or MINUS(-)/EQUAL(=) decrements/increments the frame shown.'
        '* <ctrl>+A/D, LEFT/RIGHT etc decrement/increment by 10 frames.'
        '* S or <space> accepts the labels for the current frame/target.'
        '* (The letter) O toggles occluded-estimated status.'
        '* 0..9 selects/unselects a point. When a point is selected:'
        '* ` (backquote) increments the mapping of the 0-9 hotkeys.'
        '* LEFT/RIGHT/UP/DOWN adjusts the point.'
        '* Shift-LEFT, etc adjusts the point by larger steps.' 
        '* Clicking on the image moves the selected point to that location.'};
    end
            
  end
  
  methods % template
    
    function tt = getTemplate(obj)
      % Create a template struct from current pts
      
      tt = struct();
      tt.pts = obj.getLabelCoords();
      lbler = obj.labeler;
      if lbler.hasTrx
        [x,y,th] = lbler.currentTargetLoc();
        tt.loc = [x y];
        tt.theta = th;
      else
        tt.loc = [nan nan];
        tt.theta = nan;
      end
    end
    
    function setTemplate(obj,tt)
      % Set "white points" to template.

      lbler = obj.labeler;      
      tfTemplateHasTarget = ~any(isnan(tt.loc)) && ~isnan(tt.theta);
      tfHasTrx = lbler.hasTrx;
      
      if tfHasTrx && ~tfTemplateHasTarget
        warningNoTrace('LabelCoreTemplate:template',...
          'Using template saved without target coordinates');
      elseif ~tfHasTrx && tfTemplateHasTarget
        warningNoTrace('LabelCoreTemplate:template',...
          'Template saved with target coordinates.');
      end
        
      if tfTemplateHasTarget
        [x1,y1,th1] = lbler.currentTargetLoc;
        xys = transformPoints(tt.pts,tt.loc,tt.theta,[x1 y1],th1);
      else        
        xys = tt.pts;
      end
      
      obj.assignLabelCoords(xys,'tfClip',true);
      obj.enterAdjust(LabelCoreTemplateResetType.RESET,false);
    end
    
    function setRandomTemplate(obj)
      lbler = obj.labeler;
      [x0,y0] = lbler.currentTargetLoc('nowarn',true);
      nr = lbler.movienr;
      nc = lbler.movienc;
      r = round(max(nr,nc)/6);

      n = obj.nPts;
      x = x0 + r*2*(rand(n,1)-0.5);
      y = y0 + r*2*(rand(n,1)-0.5);
      obj.assignLabelCoords([x y],'tfClip',true);
    end
    
  end
  
  methods (Access=private)
    
    function enterAdjust(obj,resetType,tfClearLabeledPos)
      % Enter adjustment state for current frame/tgt.
      %
      % resetType: LabelCoreTemplateResetType
      % if tfClearLabeledPos, clear labeled pos.
      
      if resetType > LabelCoreTemplateResetType.NORESET
        obj.setAllPointsUnadjusted(resetType);
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
         
      obj.setAllPointsAdjusted();
      obj.clearSelected();
      
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
      if ~obj.tfAdjusted(iSel)
        obj.tfAdjusted(iSel) = true;
        clr = obj.ptsPlotInfo.Colors(iSel,:);
        pv = obj.hPtsPVRegAdjustedness;
        pv.Color = clr;
        set(obj.hPts(iSel),pv);
        set(obj.hPtsOcc(iSel),pv);
        set(obj.hPtsTxt(iSel),'FontAngle','normal');
      end
    end
    
    function setAllPointsAdjusted(obj)
      clrs = obj.ptsPlotInfo.Colors;
      pv = obj.hPtsPVRegAdjustedness;
      for i=1:obj.nPts
        pv.Color = clrs(i,:);
        set(obj.hPts(i),pv);
        set(obj.hPtsOcc(i),pv);
        set(obj.hPtsTxt(i),'FontAngle','normal');
      end
      obj.tfAdjusted(:) = true;
    end
    
    function setAllPointsUnadjusted(obj,resetType)
      assert(isa(resetType,'LabelCoreTemplateResetType'));
      switch resetType
        case LabelCoreTemplateResetType.RESET
          pv = obj.hPtsPVRegAdjustedness;
          pv.Color = obj.ptsPlotInfo.TemplateMode.TemplatePointColor;
          set(obj.hPts,pv);
          set(obj.hPtsOcc,pv);
          set(obj.hPtsTxt,'FontAngle','normal');
        case LabelCoreTemplateResetType.RESETPREDICTED
          %clrs = rgbbrighten(obj.ptsPlotInfo.Colors,0);
          clrs = obj.ptsPlotInfo.Colors;
          pv = obj.hPtsPVPredAdjustedness;
          for i=1:obj.nPts
            pv.Color = clrs(i,:);
            set(obj.hPts(i),pv);
            set(obj.hPtsOcc(i),pv);
            set(obj.hPtsTxt(i),'FontAngle','italic');
          end
        otherwise
          assert(false);
      end      
      obj.tfAdjusted(:) = false;
    end
    
    function toggleEstOccPoint(obj,iPt)
      obj.tfEstOcc(iPt) = ~obj.tfEstOcc(iPt);
      obj.refreshPtMarkers('iPts',iPt);
      if obj.state==LabelState.ACCEPTED
        obj.enterAdjust(LabelCoreTemplateResetType.NORESET,false);
      end
    end
    
    function refreshTxLabelCoreAux(obj)
      iPt0 = obj.kpfIPtFor1Key;
      iPt1 = iPt0+9;
      str = sprintf('Hotkeys 0-9 map to points %d-%d',iPt0,iPt1);
      obj.txLblCoreAux.String = str;      
    end
            
  end
  
end