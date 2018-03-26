classdef ParameterVisualizationFeature < ParameterVisualization
  
  properties
    % If true, a prop for this pvObj is currently selected, and we are
    % successfully initted/displaying something.
    initSuccessful = false;
    initFeatureType; % either {'1lm' or '2lm'}    
    initFtrVizInfo % scalar struct    
    hPlot % vector of plot handles output from Features.visualize*. 
          % Set/created during init
  end
  
  methods
    
    function propSelected(obj,hAx,lObj,propFullName,sPrm)
      if obj.initSuccessful
        prmFtr = sPrm.ROOT.CPR.Feature;
        assert(strcmp(prmFtr.Type,obj.initFeatureType));
      else
        obj.init(hAx,lObj,sPrm);
      end
    end
    
    function propUnselected(obj)
      deleteValidHandles(obj.hPlot);
      obj.hPlot = [];
      obj.initSuccessful = false;
      obj.initFtrVizInfo = [];
    end

    function propUpdated(obj,hAx,lObj,propFullName,sPrm)
      prmFtr = sPrm.ROOT.CPR.Feature;
      if obj.initSuccessful && strcmp(prmFtr.Type,obj.initFeatureType)
        obj.update(hAx,lObj,sPrm);
      else
        % New init, or feature type changed
        obj.init(hAx,lObj,sPrm);
      end
    end

    function propUpdatedDynamic(obj,hAx,lObj,propFullName,sPrm,rad)
      assert(false);
%       sPrm.ROOT.CPR.Feature.Radius = rad;
%       obj.updateBase(hAx,lObj,sPrm,propFullName);
    end
    
    
    
    
    function init(obj,hAx,lObj,sPrm)
      % plot a labeled frame + viz feature for current Feature.Type.
      % Set .initSuccessful, .initFeatureType, initFtrVizInfo, .hPlot.
      % Subsequent changes to Feature.Radius or Feature.ABRatio can be 
      % handled via update(); if Feature.Type changes, init() needs to be
      % called again.

      obj.initSuccessful = false;
      obj.initFeatureType = [];
      obj.initFtrVizInfo = [];
      deleteValidHandles(obj.hPlot);
      obj.hPlot = [];
            
      if ~lObj.hasMovie
        ParameterVisualization.grayOutAxes(hAx,'No movie available.');
        return;
      end
            
      % Find a labeled frame somewhere
      frm = lObj.currFrame;
      iTgt = lObj.currTarget;
      [tffound,frm,xyLbl] = lObj.labelPosLabeledNeighbor(frm,iTgt);
      if tffound
        mIdx = lObj.currMovIdx;
        % frm,iTgt,xyLbl set
      else
        [tffound,mIdx,frm,iTgt,xyLbl] = lObj.labelFindOneLabeledFrame();
        if ~tffound
          ParameterVisualization.grayOutAxes(hAx,'No labeled frames available.');
          return;
        end
      end      
      szassert(xyLbl,[lObj.nLabelPoints 2]);
      
      % Get the image for the labeled frame, ie (mIdx,frm,iTgt)
      if lObj.currMovIdx==mIdx && lObj.currFrame==frm
        gdata = lObj.gdata;
        im = gdata.image_curr;
        im = im.CData;
      else
        IVIEW = 1;
        if lObj.currMovIdx==mIdx
          mr = lObj.movieReader(IVIEW);
        else
          mfaf = lObj.getMovieFilesAllFullMovIdx(mIdx);
          mr = MovieReader;
          lObj.movieMovieReaderOpen(mr,mfaf,IVIEW);
        end
        im = mr.readframe(frm);
      end            
      
      % We now have im and xyLbl for (mIdx,frm,iTgt)
            
      cla(hAx);
      imshow(im,'Parent',hAx);
      caxis(hAx,'auto');      
      hold(hAx,'on');
      plot(hAx,xyLbl(:,1),xyLbl(:,2),'r.','markersize',12);
      if lObj.hasTrx
        [xTrx,yTrx] = readtrx(lObj.trx,frm,iTgt);
        cropRadius = sPrm.ROOT.Track.MultiTarget.TargetCrop.Radius;
        [roixlo,roixhi,roiylo,roiyhi] = xyRad2roi(xTrx,yTrx,cropRadius);
        axis(hAx,[roixlo roixhi roiylo roiyhi]);
      end
      
      % Viz feature; set .hPlot
      nphyspts = lObj.nPhysPoints;
      nviews = lObj.nview;
      prmFtr = sPrm.ROOT.CPR.Feature;
      % generate 'fake' model parameters
      prmModel = struct('nfids',nphyspts,'d',2,'nviews',1);
      fvIfo = struct();
      fvIfo.xLM = reshape(xyLbl(:,1),1,nphyspts,nviews);
      fvIfo.yLM = reshape(xyLbl(:,2),1,nphyspts,nviews);
      GREEN = [0 1 0];
      switch prmFtr.Type
        case '1lm'
          fvIfo.xs = Features.generate1LMforSetParamViz(prmModel,...
            prmFtr.Radius);
          [xF,yF,iView,tmpInfo] = Features.compute1LM(fvIfo.xs,fvIfo.xLM,fvIfo.yLM);
          obj.hPlot = Features.visualize1LM(hAx,xF,yF,iView,tmpInfo,...
            1,1,GREEN,'doTitleStr',false,'ellipseOnly',true);
          tstr = 'Features drawn from within green circle';
        case {'2lm' 'two landmark elliptical' '2lmdiff'}
          fvIfo.tbl = Features.generate2LMellipticalForSetParamViz(prmModel,...
            prmFtr.Radius,prmFtr.ABRatio);
          [xF,yF,chan,iView,tmpInfo] = ...
            Features.compute2LMelliptical(fvIfo.tbl,fvIfo.xLM,fvIfo.yLM);
          obj.hPlot = Features.visualize2LMelliptical(hAx,xF,yF,iView,...
            tmpInfo,1,1,GREEN,'plotEllAtReff',true,'doTitleStr',false,...
            'ellipseOnly',true);
          tstr = 'Features drawn from within green ellipse';
        otherwise
          assert(false,'Unrecognized feature type.');
      end
      
      title(hAx,tstr,'interpreter','none','fontweight','normal');      
      
      obj.initSuccessful = true;
      obj.initFeatureType = prmFtr.Type;
      obj.initFtrVizInfo = fvIfo;
    end

    function update(obj,hAx,lObj,sPrm)
      % Update visualization for unchanged featuretype (eg radius, abratio
      % changed)
      
      if obj.initSuccessful
        prmFtr = sPrm.ROOT.CPR.Feature;
        assert(strcmp(prmFtr.Type,obj.initFeatureType));
        
        GREEN = [0 1 0];
        fvIfo = obj.initFtrVizInfo;
        switch prmFtr.Type
          case '1lm'
            fvIfo.xs(:,2) = prmFtr.Radius;
            [xF,yF,iView,tmpInfo] = Features.compute1LM(fvIfo.xs,fvIfo.xLM,fvIfo.yLM);
            Features.visualize1LM(hAx,xF,yF,iView,tmpInfo,1,1,[0 1 0],...
              'hPlot',obj.hPlot,'doTitleStr',false,'ellipseOnly',true);
          case {'2lm' 'two landmark elliptical' '2lmdiff'}
            tbl = fvIfo.tbl;
            tbl.reff = prmFtr.Radius;
            tbl.xeff = tbl.reff.*cos(tbl.theta);
            tbl.yeff = tbl.reff.*sin(tbl.theta)/prmFtr.ABRatio;
            
            [xF,yF,chan,iView,tmpInfo] = ...
              Features.compute2LMelliptical(tbl,fvIfo.xLM,fvIfo.yLM);
            Features.visualize2LMelliptical(hAx,xF,yF,iView,...
              tmpInfo,1,1,GREEN,'hPlot',obj.hPlot,'plotEllAtReff',true,...
              'doTitleStr',false,'ellipseOnly',true);
          otherwise
            assert(false,'Unrecognized feature type.');
        end
      end
    end
    
  end
  
end