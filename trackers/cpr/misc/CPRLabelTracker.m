classdef CPRLabelTracker < LabelTracker
  
  properties (Constant,Hidden)
    TRAINEDTRACKER_SAVEPROPS = { ...
      'sPrm' ...
      'storeFullTracking' 'showVizReplicates' ...
      'trnDataDownSamp' 'trnDataFFDThresh' 'trnDataTblP' 'trnDataTblPTS' ...
      'trnResIPt' 'trnResRC'};
    TRACKRES_SAVEPROPS = {'trkP' 'trkPFull' 'trkPTS' 'trkPTrnTS' 'trkPMD' 'trkPiPt'};
    
    DEFAULT_PARAMETER_FILE = lclInitDefaultParameterFile();
  end
  
  properties
    isInit = false; % true during load; invariants can be broken
  end
    
  %% Params
  properties (SetAccess=private)
    sPrm % full parameter struct
  end
  
  %% Note on Metadata (MD)
  %
  % There are two MD tables in CPRLabelTracker: .trnDataTblP (train) and 
  % .trkPMD (track).
  %
  % These are all MFTables (Movie-frame tables) where .mov are MovieIndex
  % arrays.
  %
  % All tables must have the key fields .mov, .frm, .iTgt. Together, these 
  % three fields act as a unique row key. The track table has only the 
  % additional optional field of .roi. The data and train tables have 
  % other additional fields such as .tfocc.
  %
  % Some defs:
  % .mov. unique ID for movie. Currently, if positive this is an index into 
  %  lObj.movieFilesAll, if negative an index into lObj.movieFilesAllGT.
  % .frm. frame number
  % .iTgt. 1-based target index (always 1 for single target proj)
  % .p. [1 x npt*nvw*d=2] labeled shape
  % .pTS. [1 x npt*nvw] timestamps for .p.
  % .tfocc. [1 x npt*nvw] occluded flags
  % Optional for multitarget:
  %   .pTrx [1x2*nview] (x,y) trx center/coord for target
  %   .roi [1x2*2*nview] square ROI in each view
  
  %% Data
  properties
    
    % Cached/working dataset. Contains all I/p/md for frames that have been
    % seen before by the tracker.
    % - Can be used for both training and tracking.
    %
    % - All frames have an image, but need not have labels (p).
    % - If applicable, all frames are HE-ed the same way.
    % - If applicable, all frames are PP-ed the same way.
    %
    % MD fields: .mov, .frm, .iTgt, .tfocc, (optional) .pTrx, (optional) .roi. 
    %data
    
    % Timestamp, last data modification (for any reason)
    %dataTS
  end
  
  %% Training Data Selection
  properties (SetObservable,SetAccess=private)
    trnDataDownSamp = false; % scalar logical.
  end
  properties
    % Furthest-first distance threshold for training data.
    trnDataFFDThresh
    
    % Currently selected training data (includes updates/additions)
    % MD fields: .mov, .frm, .iTgt, .p, .tfocc, .pTS, (opt) .pTrx, (opt) .roi
    % .mov has type MovieIndex
    trnDataTblP
    % [size(trnDataTblP,1)x1] timestamps for when rows of trnDataTblP were
    % added to CPRLabelTracker
    trnDataTblPTS
  end
    
  %% Train/Track
  properties
    % Training state -- set during .train()
%     trnResH0 % image hist used for current training results (trnResRC)
    trnResIPt % TODO doc me. Basically like .trkPiPt.
    trnResRC % [1xnView] RegressorCascade.
    
    % Tracking state -- set during .track()
    % Note: trkD here can be less than the full/model D if some pts are
    % omitted from tracking
    trkP % [NTst trkD] reduced/pruned tracked shapes. In ABSOLUTE coords
    
    % Contents depends on .storeFullTracking:
    % - If .storeFullTracking=StoreFullTrackingType.NONE, then [].
    % - If .storeFullTracking= .FINALITER, then [NTst RT trkD] double. Full
    % replicate info at final CPR iter.
    % - If .storeFullTracking= .ALLITERS, then [NTst RT trkD T+1] single. 
    % Full replicate info at all CPR iters.
    trkPFull 
    trkPTS % [NTstx1] timestamp for trkP*
    trkPTrnTS % [1xnView] trained RC timestamp for ALL results in .trkP*
    trkPMD % [NTst <ncols>] table. cols: .mov, .frm, .iTgt, (opt) .roi
           % .mov has class movieIndex 
    trkPiPt % [npttrk] indices into 1:obj.npts, tracked points. trkD=npttrk*d.
  end
  properties (SetObservable)
    storeFullTracking = StoreFullTrackingType.NONE; % scalar StoreFullTrackingType 
  end
  
  events
    % Thrown when trkP/trkPMD are mutated (basically)
    newTrackingResults 
  end
  
  %% Async
  properties
    asyncPredictOn = false; % if true, background worker is running. newLabelerFrame will fire a parfeval to predict. Could try relying on asyncBGClient.isRunning
    asyncPredictCPRLTObj; % scalar "detached" CPRLabelTracker object that is deep-copied onto workers. Contains current trained tracker used in background pred.
    asyncBGClient; % scalar BGClient object, manages comms with background worker.
  end
  properties (Dependent)
    asyncIsPrepared % If true, asyncPrepare() has been called and asyncStartBGWorker() can be called
  end
     
  %% Visualization
  properties (SetObservable)
    showVizReplicates = false; % scalar logical.
  end
  properties 
    xyPrdCurrMovie; % [npts d nfrm ntgt] predicted labels for current Labeler movie
    xyPrdCurrMovieIsInterp; % [nfrm] logical vec indicating whether xyPrdCurrMovie(:,:,i) is interpolated. Applies only when nTgts==1.
    xyPrdCurrMovieFull % [npts d nrep nfrm] predicted replicates for current Labeler movie, current target.
    hXYPrdRed; % [npts] plot handles for 'reduced' tracking results, current frame and target
    hXYPrdRedOther; % [npts] plot handles for 'reduced' tracking results, current frame, non-current-target
    hXYPrdFull; % [npts] scatter handles for replicates, current frame, current target
    xyVizPlotArgs; % cell array of args for regular tracking viz    
    xyVizPlotArgsNonTarget; % " for non current target viz
    xyVizPlotArgsInterp; % " for interpolated tracking viz
    xyVizFullPlotArgs; % " for tracking viz w/replicates. These are PV pairs for scatter() not line()
  end
  properties (Dependent)
    nPts % number of label points 
    nPtsTrk % number of tracked label points; will be <= nPts. See .trkPiPt.
    
    hasTrained
  end
    
  %% Dep prop getters
  methods
    function v = get.nPts(obj)
      v = obj.lObj.nLabelPoints;
    end
    function v = get.nPtsTrk(obj)
      v = numel(obj.trkPiPt);
    end
    function v = get.hasTrained(obj)
      v = ~isempty(obj.trnResRC) && any([obj.trnResRC.hasTrained]);
    end
    function v = get.asyncIsPrepared(obj)
      v = ~isempty(obj.asyncBGClient);
    end
  end
  methods
    function set.storeFullTracking(obj,v)
      assert(isscalar(v) && isa(v,'StoreFullTrackingType'));
      vorig = obj.storeFullTracking;
      switch v
        case StoreFullTrackingType.NONE
          if vorig>StoreFullTrackingType.NONE && ~isempty(obj.trkPFull) %#ok<MCSUP>
            warningNoTrace('CPRLabelTracker:trkPFull',...
              'Clearing stored tracking replicates.');
          end
          obj.trkPFull = []; %#ok<MCSUP>
          obj.xyPrdCurrMovieFull = []; %#ok<MCSUP>
          obj.vizClearReplicates();
        case {StoreFullTrackingType.FINALITER StoreFullTrackingType.ALLITERS}
          if isempty(obj.trkP) %#ok<MCSUP>
            assert(isempty(obj.trkPFull)); %#ok<MCSUP>
            % AL: this prob doesn't need to be its own branch
          else
            [ntrkfrm,D] = size(obj.trkP); %#ok<MCSUP>
            nrep = obj.sPrm.TestInit.Nrep; %#ok<MCSUP>
            Tp1 = obj.sPrm.Reg.T+1; %#ok<MCSUP>
            
            if vorig==StoreFullTrackingType.NONE
              warningNoTrace('CPRLabelTracker:trkPFull',...
                'Tracking results already exist; existing tracked frames will not have replicates stored.');
              if v==StoreFullTrackingType.FINALITER
                obj.trkPFull = double(nan(ntrkfrm,nrep,D)); %#ok<MCSUP>
              elseif v==StoreFullTrackingType.ALLITERS
                obj.trkPFull = single(nan(ntrkfrm,nrep,D,Tp1)); %#ok<MCSUP>
              end
            elseif vorig==StoreFullTrackingType.FINALITER
              szassert(obj.trkPFull,[ntrkfrm nrep D]); %#ok<MCSUP>
              if v==StoreFullTrackingType.ALLITERS
                warningNoTrace('CPRLabelTracker:trkPFull',...
                  'Tracking results already exist; existing tracked frames will not have replicates stored for all iterations.');
                trkPFullorig = obj.trkPFull; %#ok<MCSUP>
                obj.trkPFull = single(nan(ntrkfrm,nrep,D,Tp1)); %#ok<MCSUP>
                obj.trkPFull(:,:,:,end) = trkPFullorig; %#ok<MCSUP>
              end
            elseif vorig==StoreFullTrackingType.ALLITERS
              szassert(obj.trkPFull,[ntrkfrm nrep D Tp1]); %#ok<MCSUP>
              if v==StoreFullTrackingType.FINALITER
                warningNoTrace('CPRLabelTracker:trkPFull',...
                  'Tracking results already exist; truncating replicate storage for existing tracked frames.');
                obj.trkPFull = double(obj.trkPFull(:,:,:,end)); %#ok<MCSUP>
              end
            else
              assert(vorig==v);
            end
          end
        otherwise
          assert(false);
      end
      obj.storeFullTracking = v;
    end
  end
  
  %% Ctor/Dtor
  methods
    
    function obj = CPRLabelTracker(lObj,varargin)
      detached = myparse(varargin,...
        'detached',false);
      
      obj@LabelTracker(lObj);
      if detached
        s = struct(...
          'projMacros',lObj.projMacros,...
          'isMultiView',lObj.isMultiView,...
          'hasTrx',lObj.hasTrx,...
          'nview',lObj.nview);
        obj.lObj = s;
        obj.ax = [];
        delete(obj.hLCurrMovie);
        delete(obj.hLCurrFrame);
        delete(obj.hLCurrTarget);
        obj.hLCurrMovie = [];
        obj.hLCurrFrame = [];
        obj.hLCurrTarget = [];
      end
    end
    
    function delete(obj)
      deleteValidHandles(obj.hXYPrdRed);
      obj.hXYPrdRed = [];
      deleteValidHandles(obj.hXYPrdRedOther);
      obj.hXYPrdRedOther = [];
      deleteValidHandles(obj.hXYPrdFull);
      obj.hXYPrdFull = [];
      obj.asyncReset();
    end
    
  end
  
  %% Data  
  methods
    
    % AL 20160531 Data and timestamps
    %
    % - All labels are timestamped in the labeler (each pt has its own ts).-
    % This is done at manual-label-time (eg clicktime). The .pTS field in
    % MD tables contains this ts.
    % - .trnDataTblPTS contains timestamps labeling rows of .trnDataTblP.
    % These timestamps label when labels are accepted into the training
    % set.
    %
    % It is necessary to track this timestamp b/c the selection of a 
    % training set represents a filtering of labeled data, ie some labeled 
    % data will not be included. Once a training data set is selected,
    % moving forward we may want to find new labels made since the time of
    % that training set selection etc.
    %
    % - The RegressorCascade in .trnResRC has its own timestamps for
    % training time and so on.
    
    %#%MTGT
    %#%MV
    function [tblPnew,tblPupdate,idxTrnDataTblP] = tblPDiffTrnData(obj,tblP)
      [tblPnew,tblPupdate,idxTrnDataTblP] = MFTable.tblPDiff(obj.trnDataTblP,tblP);
    end

    function tblP = getTblPLbledRecent(obj)
      % tblP: labeled data from Labeler that is more recent than anything 
      % in .trnDataTblPTS
      
      tblP = obj.lObj.preProcGetMFTableLbled();
      maxTS = max(tblP.pTS,[],2);
      maxTDTS = max([obj.trnDataTblPTS(:);-inf]);
      tf = maxTS > maxTDTS;
      tblP = tblP(tf,:);
    end

  end
  
  %% Training Data Selection
  methods
    
    %#%MTGT
    %#%MV
    function trnDataInit(obj)
      obj.trnDataDownSamp = false;
      obj.trnDataFFDThresh = nan;
      obj.trnDataTblP = MFTable.emptyTable(MFTable.FLDSFULL);
      obj.trnDataTblPTS = -inf(0,1);
    end
    
    %#%MTGT
    function trnDataUseAll(obj)
      if obj.trnDataDownSamp
        if obj.hasTrained
          warningNoTrace('CPRLabelTracker:clear','Clearing existing tracker.');
        end
        obj.trnDataInit();
        obj.trnResInit();
        obj.trackResInit();
        obj.vizInit();
        obj.asyncReset(true);
      end
    end
    
%     %#%MTGT PROB OK not 100% sure
%     %#%MV
%     function trnDataSelect(obj)
%       % Furthest-first selection of training data.
%       %
%       % Based on user interaction, .trnDataFFDThresh, .trnDataTblP* are set.
%       % For .trnDataTblP*, this is a fresh reset, not an update.
%       
%       obj.trnResInit();
%       obj.trackResInit();
%       obj.vizInit();
%       obj.asyncReset(true);
%         
%       tblP = obj.getTblPLbled(); % start with all labeled data
%       [grps,ffd,ffdiTrl] = CPRData.ffTrnSet(tblP,[]);
%       
%       assert(all(tblP.mov>0),'Training on GT data.');
%       mov = categorical(tblP.mov); % multiview data: mov and related are multimov IDs
%       movUn = categories(mov);
%       nMovUn = numel(movUn);
%       movUnCnt = countcats(mov);
%       n = height(tblP);
%       
%       hFig = CPRData.ffTrnSetSelect(tblP,grps,ffd,ffdiTrl,...
%         'cbkFcn',@(xSel,ySel)nst(xSel,ySel));
%       
%       function nst(~,ySel)
%         % xSel/ySel: (x,y) on ffd plot nearest to user click (see
%         % CPRData.ffTrnSetSelect)
%         
%         ffdThresh = ySel;
%         assert(isscalar(ffd) && isscalar(ffdiTrl));
%         tfSel = ffd{1}>=ffdThresh;
%         iSel = ffdiTrl{1}(tfSel);
%         nSel = numel(iSel);
%         
%         tblPSel = tblP(iSel,:);
%         movSel = categorical(tblPSel.mov);
%         movUnSelCnt = arrayfun(@(x)nnz(movSel==x),movUn);
%         for iMov = 1:nMovUn
%           fprintf(1,'%s: nSel/nTot=%d/%d (%d%%)\n',char(movUn(iMov)),...
%             movUnSelCnt(iMov),movUnCnt(iMov),round(movUnSelCnt(iMov)/movUnCnt(iMov)*100));
%         end
%         fprintf(1,'Grand total of %d/%d (%d%%) shapes selected for training.\n',...
%           nSel,n,round(nSel/n*100));
%         
%         res = input('Accept this selection (y/n/c)?','s');
%         if isempty(res)
%           res = 'c';
%         end
%         switch lower(res)
%           case 'y'
%             obj.trnDataDownSamp = true;
%             obj.trnDataFFDThresh = ffdThresh;
%             obj.trnDataTblP = tblPSel;
%             obj.trnDataTblPTS = now*ones(size(tblPSel,1),1);
%           case 'n'
%             % none
%           case 'c'
%             delete(hFig);
%         end
%       end
%     end
    
  end
  
  %% TrainRes
  methods
    %#%MTGT
    function trnResInit(obj)
      if isempty(obj.sPrm)
        obj.trnResRC = [];
      else
        nview = obj.lObj.nview;
        sPrmUse = obj.sPrm;
        %sPrmUse.Model.nfids = sPrmUse.Model.nfids/nview;
        sPrmUse.Model.nviews = 1;
        for i=1:nview
          rc(1,i) = RegressorCascade(sPrmUse); %#ok<AGROW>
        end
        obj.trnResRC = rc;
      end
      obj.trnResIPt = [];
%       obj.trnResH0 = [];
      
      obj.asyncReset();
    end
  end
  
  %% TrackRes
  methods

    function setAllTrackResTable(obj,tblTrkRes,pTrkiPt)
      % Set all current tracking results in a table. 
      % USE WITH EXTREME CAUTION
      %
      % tblTrkRes: [NTrk x ncol] table of tracking results. Flds 
      %   'mov','frm','iTgt',(opt) 'roi','pTrk'. pTrk like obj.trkP; 
      %    ABSOLUTE coords
      % pTrkiPt: [npttrk] indices into 1:obj.npts, tracked points. 
      %          size(tblTrkRes.pTrk,2)==npttrk*d

      tblfldscontainsassert(tblTrkRes,[MFTable.FLDSID 'pTrk']);
      fldsMD = MFTable.FLDSID;
      if tblfldscontains(tblTrkRes,'roi')
        fldsMD{end+1} = 'roi';
      end
      
      nTrk = height(tblTrkRes);
      assert(size(tblTrkRes.pTrk,2)==numel(pTrkiPt)*2);
      
      obj.trkPMD = tblTrkRes(:,fldsMD);
      obj.trkP = tblTrkRes.pTrk;
      obj.trkPTS = repmat(now,nTrk,1);
      obj.trkPTrnTS = nan(1,obj.lObj.nview);
      obj.trkPiPt = pTrkiPt;
      switch obj.storeFullTracking
        case StoreFullTrackingType.NONE
          obj.trkPFull = [];
        case StoreFullTrackingType.FINALITER
          warningNoTrace('CPRLabelTracker:trk','Full tracking results not set.');
          [ntrkfrm,D] = size(obj.trkP);
          nrep = obj.sPrm.TestInit.Nrep;
          obj.trkPFull = nan(ntrkfrm,nrep,D);
        case StoreFullTrackingType.ALLITERS
          warningNoTrace('CPRLabelTracker:trk','Full tracking results not set.');
          [ntrkfrm,D] = size(obj.trkP);
          nrep = obj.sPrm.TestInit.Nrep;
          Tp1 = obj.sPrm.Reg.T+1;
          obj.trkPFull = single(nan(ntrkfrm,nrep,D,Tp1));
        otherwise
          assert(false);
      end          
      
      obj.vizLoadXYPrdCurrMovieTarget();
      obj.newLabelerFrame();
      notify(obj,'newTrackingResults');
    end
    
    function [tblTrkRes,pTrkiPt] = getAllTrackResTable(obj) % obj const
      % Get all current tracking results in a table
      %
      % tblTrkRes: [NTrk x ncol] table of tracking results
      %            .pTrk, like obj.trkP; ABSOLUTE coords
      % pTrkiPt: [npttrk] indices into 1:obj.npts, tracked points. 
      %          size(tblTrkRes.pTrk,2)==npttrk*d

      tblTrkRes = obj.trkPMD;
      tblTrkRes.pTrk = obj.trkP;
      tblTrkRes.pTrkTS = obj.trkPTS;
      tblTrkRes.pTrkTrnTS = repmat(obj.trkPTrnTS,height(tblTrkRes),1);
      pTrkiPt = obj.trkPiPt;
    end
    
    %#%MTGT
    %#%MV
    function [trkpos,trkposTS,trkposFull,trkposFullMFT,trkposTrnTS,tfHasRes] = ...
        getTrackResRaw(obj,mIdx)
      % Get tracking results for movie(set) iMov.
      %
      % mIdx: scalar MovieIndex
      % 
      % trkpos: [nptstrk x d x nfrm(iMov) x ntgt(iMov)]. Tracking results 
      % for iMov. 
      %  IMPORTANT: first dim is nptstrk=numel(.trkPiPt), NOT obj.npts. If
      %  movies in a movieset have differing numbers of frames, then nfrm
      %  will equal the minimum number of frames across the movieset.
      % trkposTS: [nptstrk x nfrm(iMov) x ntgt(iMov)]. Timestamps for trkpos.
      % trkposFull: [nptstrk x d x nRep x nTrkRows]. 
      %   Currently this is all nans if .storeFullTracking is
      %   StoreFullTrackingType.NONE. Note also this may be of type single 
      %   or double.
      % trkposFullMFT: MFTable (height nTrkRows) labeling 4th dim of
      %   trkposFull
      % tfHasRes: if true, nontrivial tracking results returned
            
      lObj = obj.lObj;

      assert(isscalar(mIdx) && isa(mIdx,'MovieIndex'));
      nfrms = lObj.getNFramesMovIdx(mIdx);
      lpos = lObj.getLabeledPosMovIdx(mIdx);
      assert(size(lpos,3)==nfrms);
      ntgts = size(lpos,4);

      pTrk = obj.trkP;
      [NTrk,DTrk] = size(pTrk);
      trkMD = obj.trkPMD;
      iPtTrk = obj.trkPiPt;
      nPtTrk = numel(iPtTrk);
      d = 2;
      assert(height(trkMD)==NTrk);
      assert(nPtTrk*d==DTrk);
          
      nRep = obj.sPrm.TestInit.Nrep;
      if isempty(obj.trkPFull)
        pTrkFull = nan(NTrk,nRep,DTrk);
      else
        switch obj.storeFullTracking
          case StoreFullTrackingType.FINALITER
            pTrkFull = obj.trkPFull;
          case StoreFullTrackingType.ALLITERS
            pTrkFull = obj.trkPFull(:,:,:,end);
          otherwise
            assert(false);
        end
      end
      szassert(pTrkFull,[NTrk nRep DTrk]);
      
      assert(numel(obj.trkPTS)==NTrk);

      trkpos = nan(nPtTrk,d,nfrms,ntgts);
      trkposTS = -inf(nPtTrk,nfrms,ntgts);
      
      tfCurrMov = trkMD.mov==mIdx;
      trkMDCurrMov = trkMD(tfCurrMov,:);
      nRowCurrMov = height(trkMDCurrMov);
      trkposFull = nan(nPtTrk,d,nRep,nRowCurrMov,class(pTrkFull));
      trkposFullMFT = trkMDCurrMov(:,MFTable.FLDSID);
      trkposTrnTS = nan(1,lObj.nview);
      
      % First cond is proxy for no tracking results 
      tfHasRes = ~isempty(obj.trkPTS) && (nRowCurrMov>0);
      if tfHasRes
        xyTrkCurrMov = reshape(pTrk(tfCurrMov,:)',nPtTrk,d,nRowCurrMov);
        trkPTSCurrMov = obj.trkPTS(tfCurrMov);
        pTrkFullCurrMov = pTrkFull(tfCurrMov,:,:); % [nRowCurrMov nRep D]
        pTrkFullCurrMov = permute(pTrkFullCurrMov,[3 2 1]); % [D nRep nRowCurrMov]
        trkposFull = reshape(pTrkFullCurrMov,[nPtTrk d nRep nRowCurrMov]);
        tfEmptyRow = arrayfun(@(x)nnz(~isnan(trkposFull(:,:,:,x)))==0,...
          (1:nRowCurrMov)');
        trkposFull(:,:,:,tfEmptyRow) = [];
        % AL20170926: ML2015b table subsasgn but where first col is of type
        % MovieIndex. Row-deletion using subasgn appears impossible on any 
        % table containing MovieIndex objects in a column.
        % 
        % trkposFullMFT(tfEmptyRow,:) = [];
        trkposFullMFT = trkposFullMFT(~tfEmptyRow,:);
        for i=1:nRowCurrMov
          frm = trkMDCurrMov.frm(i);
          iTgt = trkMDCurrMov.iTgt(i);
          trkpos(:,:,frm,iTgt) = xyTrkCurrMov(:,:,i);
          trkposTS(:,frm,iTgt) = trkPTSCurrMov(i);
        end
        
        szassert(obj.trkPTrnTS,size(trkposTrnTS));
        trkposTrnTS = obj.trkPTrnTS;
      end
    end
    
    %#%MTGT
    function trkposFull = getTrackResFullCurrTgt(obj,mIdx,frm)
      % Get full tracking results for movie iMov, frame frm, curr tgt.
      % Note, only the final CPR iter may be available depending on
      % .storeFullTracking.
      %
      % iMov: scalar movie index (negative for GT movies)
      % 
      % trkposFull: [nptstrk x d x nRep x (T+1)], or [] if iMov/frm not
      % found in .trkPFull'
      
      assert(isscalar(mIdx) && isa(mIdx,'MovieIndex'));
      switch obj.storeFullTracking
        case {StoreFullTrackingType.ALLITERS StoreFullTrackingType.FINALITER}
          % none; ok         
        otherwise
          error('No replicate data is currently stored.');
      end
      
      trkMD = obj.trkPMD;
      iPtTrk = obj.trkPiPt;
      nPtTrk = numel(iPtTrk);
      d = 2;
      nRep = obj.sPrm.TestInit.Nrep;
      
      lObj = obj.lObj;
      iTgt = lObj.currTarget;

      tfMovFrm = trkMD.mov==mIdx & trkMD.frm==frm & trkMD.iTgt==iTgt;
      nMovFrm = nnz(tfMovFrm);
      assert(nMovFrm==0 || nMovFrm==1);
            
      if nMovFrm==0
        trkposFull = [];
      else
        switch obj.storeFullTracking
          case StoreFullTrackingType.ALLITERS
            trkposFull = squeeze(obj.trkPFull(tfMovFrm,:,:,:)); % [nRep Dtrk Tp1]
          case StoreFullTrackingType.FINALITER
            Tp1 = obj.sPrm.Reg.T+1;
            trkposFull = nan(nRep,nPtTrk*d,Tp1);
            trkposFull(:,:,end) = squeeze(obj.trkPFull(tfMovFrm,:,:));
        end
        Tp1 = size(trkposFull,3);
        trkposFull = reshape(trkposFull,[nRep nPtTrk d Tp1]);
        trkposFull = permute(trkposFull,[2 3 1 4]);
      end
    end
    
    %#%MTGT
    function updateTrackRes(obj,tblMFtrk,pTstTRed,pTstT,pTstTTrnTS)
      % Augment .trkP* state with new tracking results
      %
      % tblMF: [nTst x nCol] MF table for pTstTRed/pTstT
      % pTstTRed: [nTst x Dfull]
      % pTstT: [nTst x RT x Dfull x Tp1]
      % pTstTTrnTS: [1xnView] training timestamps
      % 
      % - new rows are just added
      % - existing rows are overwritten
            
      nTst = height(tblMFtrk);
      RT = obj.sPrm.TestInit.Nrep;
      mdlPrms = obj.sPrm.Model;
      Dfull = mdlPrms.nfids*mdlPrms.nviews*mdlPrms.d;
      Tp1 = obj.sPrm.Reg.T+1;
      szassert(pTstTRed,[nTst Dfull]);
      szassert(pTstT,[nTst RT Dfull Tp1]);
      
      tfROI = tblfldscontains(tblMFtrk,'roi');
      if tfROI
        % Convert pTstT and pTstTRed from relative/ROI coords to absolute
        % coords
        assert(mdlPrms.d==2);
        npts = mdlPrms.nfids*mdlPrms.nviews;
        xyTmp = reshape(pTstTRed,[nTst npts 2]);
        xyTmp = permute(xyTmp,[2 3 1]);
        xyTmp = Shape.xyRoi2xy(xyTmp,tblMFtrk.roi); % npt x 2 x nTst
        xyTmp = permute(xyTmp,[3 1 2]);
        pTstTRed = reshape(xyTmp,[nTst Dfull]);
        
        xyTmp = reshape(pTstT,[nTst RT npts 2 Tp1]);
        xyTmp = permute(xyTmp,[3 4 1 2 5]); % [npts 2 nTst RT Tp1]
        xyTmp = reshape(xyTmp,[npts 2 nTst*RT*Tp1]);
        xyTmp = Shape.xyRoi2xy(xyTmp,repmat(tblMFtrk.roi,RT*Tp1,1));
        xyTmp = reshape(xyTmp,[npts 2 nTst RT Tp1]);
        xyTmp = permute(xyTmp,[3 4 1 2 5]); % [nTst RT npts 2 Tp1]
        pTstT = reshape(xyTmp,[nTst RT Dfull Tp1]);
      end

      if ~isempty(obj.trkP)
        assert(~isempty(obj.trkPiPt),...
          'Tracked points specification (.trkPiPt) cannot be empty.');
        if ~isequal(obj.trkPiPt,obj.trnResIPt) % TODO: conceptually the second arg should be passed in. This assumes the tracking-points-to-be-added come from a particular source
          error('CPRLabelTracker:track',...
            'Existing tracked points (.trkPiPt) differ from new tracked points. New tracking results cannot be saved.');
        end
      end
      
      [tf,loc] = tblismember(tblMFtrk,obj.trkPMD,MFTable.FLDSID);
      
      % existing rows
      idxCur = loc(tf);
      obj.trkP(idxCur,:) = pTstTRed(tf,:);
      switch obj.storeFullTracking
        case StoreFullTrackingType.NONE
          assert(isempty(obj.trkPFull));
        case StoreFullTrackingType.FINALITER
          if ~isequal(obj.trkPFull,[])
            szassert(obj.trkPFull,[size(obj.trkP,1) RT Dfull]);
          end
          obj.trkPFull(idxCur,:,:) = pTstT(tf,:,:,end);
        case StoreFullTrackingType.ALLITERS
          if ~isequal(obj.trkPFull,[])
            szassert(obj.trkPFull,[size(obj.trkP,1) RT Dfull Tp1]);
          end
          obj.trkPFull(idxCur,:,:,:) = single(pTstT(tf,:,:,:));    
        otherwise
          assert(false);
      end      
      
      nowts = now;
      obj.trkPTS(idxCur) = nowts;
      % new rows
      obj.trkP = [obj.trkP; pTstTRed(~tf,:)];
      switch obj.storeFullTracking
        case StoreFullTrackingType.FINALITER
          obj.trkPFull = [obj.trkPFull; pTstT(~tf,:,:,end)];
        case StoreFullTrackingType.ALLITERS
          obj.trkPFull = [obj.trkPFull; single(pTstT(~tf,:,:,:))];
      end
      nNew = nnz(~tf);
      obj.trkPTS = [obj.trkPTS; repmat(nowts,nNew,1)];
      if all(isnan(obj.trkPTrnTS))
        obj.trkPTrnTS = pTstTTrnTS;        
      else
        % Currently, all tracking results must come from the same
        % tracker(s)
        assert(isequal(obj.trkPTrnTS,pTstTTrnTS));
      end
      if isempty(obj.trkPMD)
        % .trkPMD might not be initted with the .roi col in the multitarget
        % case
        obj.trkPMD = tblMFtrk(~tf,:); 
      else
        obj.trkPMD = tblvertcatsafe(obj.trkPMD,tblMFtrk(~tf,:));
      end

      % See above check/error re .trkPiPt. Either there were originally no
      % tracking results so we are setting .trkPiPt for the first time; or
      % there were original tracking results and the old .trkPiPt matches
      % the new (in which case this line is a no-op).
      % TODO: again should not assume where results are coming from
      obj.trkPiPt = obj.trnResIPt;
    end
    
  end
  
  %% LabelTracker overloads
  methods
    
    %#%MTGT
    %#%MV
    function initHook(obj)
      % "config init"
      %obj.storeFullTracking = obj.lObj.projPrefs.CPRLabelTracker.StoreFullTracking;      
      
      obj.trnDataInit();
      obj.trnResInit();
      obj.trackResInit();
      obj.vizInit();
      obj.asyncReset();
    end
        
%     %#%MTGT
%     function setParams(obj,sPrm)
%       % sPrm must be FULLY MODERNIZED
%       obj.setParamContentsSmart(sPrm);
%       obj.paramFile = '';
%     end
    
    function sPrm = getParams(obj)
      sPrm = obj.sPrm;
    end
    
    %#%MV
    function setParamContentsSmart(obj,sNew,tfPreProcPrmsChanged)
      % Set parameter contents (.sPrm), looking at what top-level fields 
      % have changed and clearing obj state appropriately.
      %
      % sNew: scalar struct, parameters
      % tfPreProcPrmsChanged: scalar logical. If true, preprocessing
      % parameters changed. See PreProc notes in Labeler.m
      
      sOld = obj.sPrm;
      obj.sPrm = sNew; % set this now so eg trnResInit() can use
      
      if isempty(sOld) || isempty(sNew)
        %obj.initData();
        obj.trnDataInit();
        obj.trnResInit();
        obj.trackResInit();
        obj.vizInit();
        obj.asyncReset();
      else % Both sOld, sNew nonempty
        if sNew.Model.nviews~=obj.lObj.nview
          error('CPRLabelTracker:nviews',...
            'Number of views in parameters.Model (%d) does not match number of views in project (%d).',...
            sNew.Model.nviews,obj.lObj.nview);
        end
        if sNew.Model.nfids~=obj.lObj.nPhysPoints
          error('CPRLabelTracker:npts',...
            'Number of points in parameters.Model (%d) does not match number of physical points in project (%d).',...
            sNew.Model.nfids,obj.lObj.nPhysPoints);
        end
        
        if isempty(sOld.Model.nviews)
          sOld.Model.nviews = 1;
          % set this to enable comparisons below
        end
      
        % Figure out what changed
        flds = fieldnames(sOld);
        tfunchanged = struct();
        for f=flds(:)',f=f{1}; %#ok<FXSET>
          tfunchanged.(f) = isequaln(sOld.(f),sNew.(f));
        end
        
        % data
        modelPPUC = tfunchanged.Model && ~tfPreProcPrmsChanged;
        if ~modelPPUC
          %fprintf(2,'Parameter change: CPRLabelTracker data cleared.\n');
          %obj.initData();
          obj.asyncReset();
        end
        
        % trainingdata
        if ~modelPPUC
          fprintf(2,'Parameter change: CPRLabelTracker training data selection cleared.\n');
          obj.trnDataInit();
        end
      
        % trnRes
        modelPPRegFtrTrnInitUC = modelPPUC && tfunchanged.Reg ...
            && tfunchanged.Ftr && tfunchanged.TrainInit;
        if ~modelPPRegFtrTrnInitUC
          fprintf(2,'Parameter change: CPRLabelTracker regressor casacade cleared.\n');
          obj.trnResInit();
        end
      
        % trkP
        if ~(modelPPRegFtrTrnInitUC && tfunchanged.TestInit && tfunchanged.Prune)
          fprintf(2,'Parameter change: CPRLabelTracker tracking results cleared.\n');
          obj.trackResInit();
          obj.vizInit();
          obj.asyncReset();
        end
      end
    end
     
    %#%MTGT
    function trainingDataMontage(obj)
      labelerObj = obj.lObj;
      
      if labelerObj.isMultiView
        error('CPRLabelTracker:multiview',...
          'Currently unsupported for multiview projects.');
      end
      tblTrn = obj.trnDataTblP;
      if isempty(tblTrn) || ~obj.hasTrained
        msgbox('Please train a tracker first.');
        return;
      end
      
      [d,iTrn] = labelerObj.preProcDataFetch(tblTrn);
      nTrn = numel(iTrn);
      fprintf(1,'%d training rows in total.\n',nTrn);
      
      if nTrn>=48
        nrMtg = 6;
        ncMtg = 8;
      else
        nrMtg = floor(sqrt(nTrn));      
        ncMtg = floor(nTrn/nrMtg);
      end
      Shape.montage(d.I(iTrn,:),d.pGT(iTrn,:),'nr',nrMtg,'nc',ncMtg,...
        'titlestr','Training Data Montage')  
    end
    
    %#%MTGT
    function retrain(obj,varargin)
      % Full train 
      % 
      % Sets .trnRes*
      
      [tblPTrn,updateTrnData,wbObj] = myparse(varargin,...
        'tblPTrn',[],... % optional MFTp table of training data. if supplied, set .trnData* state based on this table
        'updateTrnData',true,... % if false, don't check for new/recent Labeler labels. Used only when .trnDataDownSamp is true (and tblPTrn not supplied).
        'wbObj',[] ... % optional WaitBarWithCancel. If cancel:
                   ... % 1. .trnDataInit() and .trnResInit() are called
                   ... % 2. .lObj.preProcData may be updated but that should be OK
        );
      tfWB = ~isempty(wbObj);
      
      prm = obj.sPrm;
      if isempty(prm)
        error('CPRLabelTracker:param','Please specify tracking parameters.');
      end
      
      obj.asyncReset(true);
       
      if isempty(tblPTrn) && obj.trnDataDownSamp
        assert(~obj.lObj.hasTrx,'Downsampling currently unsupported for projects with trx.');
        if updateTrnData
          % first, update the TrnData with any new labels
          tblPNew = obj.getTblPLbledRecent();
          [tblPNewTD,tblPUpdateTD,idxTrnDataTblP] = obj.tblPDiffTrnData(tblPNew);
          if ~isempty(idxTrnDataTblP) % AL 20160912: conditional should not be necessary, MATLAB API bug
            obj.trnDataTblP(idxTrnDataTblP,:) = tblPUpdateTD;
          end
          obj.trnDataTblP = [obj.trnDataTblP; tblPNewTD];
          nowtime = now();
          nNewRows = size(tblPNewTD,1);
          obj.trnDataTblPTS(idxTrnDataTblP) = nowtime;
          obj.trnDataTblPTS = [obj.trnDataTblPTS; nowtime*ones(nNewRows,1)];
          fprintf('Updated training data with new labels: %d updated rows, %d new rows.\n',...
            size(tblPUpdateTD,1),nNewRows);
        end
        tblPTrn = obj.trnDataTblP;
      else % Either use supplied tblPTrn, or use all labeled data
        if isempty(tblPTrn)
          % use all labeled data
          tblPTrn = obj.lObj.preProcGetMFTableLbled('wbObj',wbObj);
          if tfWB && wbObj.isCancel
            % Theoretically we are safe to return here as of 201801. We 
            % have only called obj.asyncReset() so far. 
            % However to be conservative/nonfragile/consistent let's reset 
            % as in other cancel/early-exits
            obj.trnDataInit();
            obj.trnResInit();
            return;
          end
        end
        if obj.lObj.hasTrx
          tblfldscontainsassert(tblPTrn,[MFTable.FLDSCOREROI {'thetaTrx'}]);
        else
          tblfldscontainsassert(tblPTrn,MFTable.FLDSCORE);
        end

        obj.trnDataFFDThresh = nan;
        % still set .trnDataTblP, .trnDataTblPTS to enable incremental
        % training
        obj.trnDataTblP = tblPTrn;
        nowtime = now();
        obj.trnDataTblPTS = nowtime*ones(height(tblPTrn),1);
      end
                
      if isempty(tblPTrn)
        error('CPRLabelTracker:noTrnData','No training data set.');
      end
      fprintf(1,'Training with %d rows.\n',height(tblPTrn));
      
      [d,dIdx] = obj.lObj.preProcDataFetch(tblPTrn,'wbObj',wbObj);
      if tfWB && wbObj.isCancel
        obj.trnDataInit();
        obj.trnResInit();
        return;
      end
        
%       [tf,locDataInTblP] = tblismember(d.MD,tblPTrn,MFTable.FLDSID);
%       assert(nnz(tf)==height(tblPTrn));
      d.iTrn = dIdx;
%       locDataInTblP = locDataInTblP(tf);
      
      fprintf(1,'Training data summary:\n');
      d.summarize('mov',d.iTrn);
      
      %[Is,nChan] = d.getCombinedIs(d.iTrn);
      [Is,nChan] = d.getCombinedIsMat(d.iTrn);
      prm.Ftr.nChn = nChan;
      
      iPt = prm.TrainInit.iPt;
      nfids = prm.Model.nfids;
      nviews = prm.Model.nviews;
      assert(prm.Model.d==2);
      nfidsInTD = size(d.pGT,2)/prm.Model.d;
      if isempty(iPt)
        assert(nfidsInTD==nfids*nviews);
        iPt = 1:nfidsInTD;
      else
        assert(obj.lObj.nview==1,'TrainInit.iPt specification currently unsupported for multiview projects.');
      end
      iPGT = [iPt iPt+nfidsInTD];
      fprintf(1,'iPGT: %s\n',mat2str(iPGT));
      pTrn = d.pGTTrn(:,iPGT);
      % pTrn col order is: [iPGT(1)_x iPGT(2)_x ... iPGT(end)_x iPGT(1)_y ... iPGT(end)_y]
      
      nView = obj.lObj.nview;
      if nView==1 % doesn't need its own branch, just leaving old path
        % expect a permutation
        %assert(isequal(sort(locDataInTblP(:)'),1:height(tblPTrn))); %#ok<TRSRT>
        %tblPTrnPerm = tblPTrn(locDataInTblP,:);
        assert(isequal(d.MDTrn(:,MFTable.FLDSID),tblPTrn(:,MFTable.FLDSID)));
        if tblfldscontains(tblPTrn,'thetaTrx')
          oThetas = tblPTrn.thetaTrx;
        else
          oThetas = [];
        end
        obj.trnResRC.trainWithRandInit(Is,d.bboxesTrn,pTrn,...
          'orientationThetas',oThetas,'wbObj',wbObj);
        if tfWB && wbObj.isCancel
          % .trnResRC in indeterminate state
          obj.trnDataInit();
          obj.trnResInit();         
          return;
        end        
      else
        assert(~obj.lObj.hasTrx,'Currently unsupported for projects with trx.');
        assert(size(Is.imoffs,2)==nView);
        assert(size(pTrn,2)==obj.lObj.nPhysPoints*nView*prm.Model.d); 
        assert(nfidsInTD==obj.lObj.nPhysPoints*nView);
        % col order of pTrn should be:
        % [p1v1_x p2v1_x .. pkv1_x p1v2_x .. pkv2_x .. pkvW_x
        nPhysPoints = obj.lObj.nPhysPoints;
        for iView=1:nView
          IsVw = Is;
          IsVw.imszs = IsVw.imszs(:,:,iView);
          IsVw.imoffs = IsVw.imoffs(:,iView);
          bbVw = CPRData.getBboxes2D(IsVw);
          iPtVw = (1:nPhysPoints)+(iView-1)*nPhysPoints;
          assert(isequal(iPtVw(:),find(obj.lObj.labeledposIPt2View==iView)));
          pTrnVw = pTrn(:,[iPtVw iPtVw+nfidsInTD]);
          
          % Future todo: orientationThetas
          % Should break internally if 'orientationThetas' is req'd
          obj.trnResRC(iView).trainWithRandInit(IsVw,bbVw,pTrnVw,'wbObj',wbObj);
          if tfWB && wbObj.isCancel
            % .trnResRC in indeterminate state
            obj.trnDataInit();
            obj.trnResInit();
            return;
          end
        end
      end
      obj.trnResIPt = iPt;
    end
    
    %#%MTGT
    function train(obj,varargin)
      % Incremental trainupdate using labels newer than .trnDataTblPTS

      prm = obj.sPrm;
      if isempty(prm)
        error('CPRLabelTracker:param','Please specify tracking parameters.');
      end
        
      % figure out if we want an incremental train or full retrain
      rc = obj.trnResRC;
      if any(~[rc.hasTrained])
        error('No tracker has been trained. Cannot do an incremental training update.');
        % We don't want to just call retrain here, as a real retrain
        % may require PP actions (eg histeq)
      end
      
      obj.asyncReset(true);
            
      assert(obj.lObj.nview==1,...
        'Incremental training currently unsupported for multiview projects.');
      assert(~obj.lObj.hasTrx,...
        'Incremental training currently unsupported for multitarget projects.');      
      
      tblPNew = obj.getTblPLbledRecent();
      
      if isempty(tblPNew)
        msgbox('Trained tracker is up-to-date with labels.','Train');
        return;
      end
      
      %%% do incremental train
      
      % update the TrnData
      [tblPNewTD,tblPUpdateTD,idxTrnDataTblP] = obj.tblPDiffTrnData(tblPNew);
      if ~isempty(idxTrnDataTblP) % AL: conditional should not be necessary, MATLAB API bug
        obj.trnDataTblP(idxTrnDataTblP,:) = tblPUpdateTD;
      end
      obj.trnDataTblP = [obj.trnDataTblP; tblPNewTD];
      nowtime = now();
      obj.trnDataTblPTS(idxTrnDataTblP) = nowtime;
      obj.trnDataTblPTS = [obj.trnDataTblPTS; nowtime*ones(size(tblPNewTD,1),1)];
      
      % print out diagnostics on when training occurred etc
      iTL = rc.trnLogMostRecentTrain();
      tsFullTrn = rc.trnLog(iTL).ts;
      fprintf('Most recent full train at %s\n',datestr(tsFullTrn,'mmm-dd-yyyy HH:MM:SS'));
      obj.trainPrintDiagnostics(iTL);
     
      [d,dIdx] = obj.lObj.preProcDataFetch(tblPNew);
      d.iTrn = dIdx;      
      fprintf(1,'Training data summary:\n');
      d.summarize('mov',d.iTrn);
      
      % Call rc.train with 'update', true 
      [Is,nChan] = d.getCombinedIs(d.iTrn);
      prm.Ftr.nChn = nChan;
            
      iPt = prm.TrainInit.iPt;
      nfids = prm.Model.nfids;
      assert(prm.Model.d==2);
      nfidsInTD = size(d.pGT,2)/prm.Model.d;
      if isempty(iPt)
        assert(nfidsInTD==nfids);
        iPt = 1:nfidsInTD;
      end
      iPGT = [iPt iPt+nfidsInTD];
      fprintf(1,'iPGT: %s\n',mat2str(iPGT));
      
      pTrn = d.pGTTrn(:,iPGT);

      % future todo: orientationThetas
      % Should break internally if 'orientationThetas' is req'd
      rc = obj.trnResRC;
      rc.trainWithRandInit(Is,d.bboxesTrn,pTrn,'update',true,'initpGTNTrn',true);

      %obj.trnResTS = now;
      %obj.trnResPallMD = d.MD;
      assert(isequal(obj.trnResIPt,iPt));
    end
    
    %#%MTGT
    %#%MV
    function trainPrintDiagnostics(obj,iTL)
      % iTL: Index into .trnLog at which to start
      
      rc = obj.trnResRC(1);
      tsFullTrn = rc.trnLog(iTL).ts;

      nTL = numel(rc.trnLog);
      tsTrnDataUn = unique(obj.trnDataTblPTS);
      tsTrnDataUn = tsTrnDataUn(tsTrnDataUn>=tsFullTrn); % trn data updates after most recent fulltrain
      tsTrnDataUn = sort(tsTrnDataUn);
      ntsTrnData = numel(tsTrnDataUn);
      itsTD = 0;
      while iTL<nTL || itsTD<ntsTrnData
        if iTL==nTL
          action = 'trnData';
        elseif itsTD==ntsTrnData
          action = 'trnLog';
        elseif rc.trnLog(iTL+1).ts<tsTrnDataUn(itsTD+1)
          action = 'trnLog';
        else
          action = 'trnData';
        end
        
        switch action
          case 'trnLog'
            fprintf('%s at %s\n',rc.trnLog(iTL+1).action,...
              datestr(rc.trnLog(iTL+1).ts,'mmm-dd-yyyy HH:MM:SS'));
            iTL = iTL+1;
          case 'trnData'
            ntmp = nnz(obj.trnDataTblPTS==tsTrnDataUn(itsTD+1));
            fprintf('%d labels added to training data at %s\n',ntmp,...
              datestr(tsTrnDataUn(itsTD+1),'mmm-dd-yyyy HH:MM:SS'));
            itsTD = itsTD+1;
        end
      end
    end
    
    % BGKD -- PROB JUST USE TRACK
    function [trkPMDnew,pTstTRed,pTstT] = trackCore(obj,tblP)
      prm = obj.sPrm;
      if isempty(prm)
        error('CPRLabelTracker:param','Please specify tracking parameters.');
      end
      if ~all([obj.trnResRC.hasTrained])
        error('CPRLabelTracker:track','No tracker has been trained.');
      end
                            
      %%% data
      [d,dataIdx] = obj.lObj.preProcDataFetch(tblP);
      d.iTst = dataIdx;
      fprintf(1,'Track data summary:\n');
      d.summarize('mov',d.iTst);
                
      [Is,nChan] = d.getCombinedIs(d.iTst);
      prm.Ftr.nChn = nChan;
        
      %% Test on test set; fill/generate pTstT/pTstTRed for this chunk
      NTst = d.NTst;
      RT = prm.TestInit.Nrep;
      nview = obj.sPrm.Model.nviews;
      nfids = prm.Model.nfids;
      assert(nview==numel(obj.trnResRC));
      assert(nview==size(Is,2));
      assert(prm.Model.d==2);
      Dfull = nfids*nview*prm.Model.d;
      pTstT = nan(NTst,RT,Dfull,prm.Reg.T+1);
      pTstTRed = nan(NTst,Dfull);
      pTstTPruneMD = array2table(nan(NTst,0));
      for iView=1:nview % obj CONST over this loop
        rc = obj.trnResRC(iView);
        IsVw = Is(:,iView);
        bboxesVw = CPRData.getBboxes2D(IsVw);
        if nview==1
          assert(isequal(bboxesVw,d.bboxesTst));
        end
          
        % Future todo, orientationThetas
        % Should break internally if 'orientationThetas' is req'd
        [p_t,pIidx,p0,p0Info] = rc.propagateRandInit(IsVw,bboxesVw,...
          prm.TestInit);

        trkMdl = rc.prmModel;
        trkD = trkMdl.D;
        Tp1 = rc.nMajor+1;
        pTstTVw = reshape(p_t,[NTst RT trkD Tp1]);
        
        %% Prune
        [pTstTRedVw,pruneMD] = CPRLabelTracker.applyPruning(...
          pTstTVw(:,:,:,end),d.MDTst(:,MFTable.FLDSID),prm.Prune);
        szassert(pTstTRedVw,[NTst trkD]);
        if nview>1
          pruneMD = tblfldsmodify(pruneMD,@(x)[x '_vw' num2str(iView)]);
        end
        pTstTPruneMD = [pTstTPruneMD pruneMD]; %#ok<AGROW>        
        
        assert(trkD==Dfull/nview);
        assert(mod(trkD,2)==0);
        iFull = (1:nfids)+(iView-1)*nfids;
        iFull = [iFull,iFull+nfids*nview]; %#ok<AGROW>
        pTstT(:,:,iFull,:) = pTstTVw;
        pTstTRed(:,iFull) = pTstTRedVw;
      end % end obj CONST
        
      fldsTmp = MFTable.FLDSID;
      if any(strcmp(d.MDTst.Properties.VariableNames,'roi'))
        fldsTmp{1,end+1} = 'roi';
      end
      trkPMDnew = d.MDTst(:,fldsTmp);
      trkPMDnew = [trkPMDnew pTstTPruneMD];
      obj.updateTrackRes(trkPMDnew,pTstTRed,pTstT); % XXX out of date api
    end
    
    %#%MTGT
    %#%MV
    function trackOld(obj,tblMFT,varargin)
      % tblMFT: MFtable. Req'd flds: MFTable.ID.
      
      [movChunkSize,p0DiagImg,wbObj] = myparse(varargin,...
        'movChunkSize',5000, ... % track large movies in chunks of this size
        'p0DiagImg',[], ... % full filename; if supplied, create/save a diagnostic image of initial shapes for first tracked frame
        'wbObj',[] ... % WaitBarWithCancel. If cancel:
                   ... %  1. .lObj.preProcData might be cleared
                   ... %  2. tracking results may be partally updated
        );
      tfWB = ~isempty(wbObj);
      
      prm = obj.sPrm;
      if isempty(prm)
        error('CPRLabelTracker:param','Please specify tracking parameters.');
      end
      if ~all([obj.trnResRC.hasTrained])
        error('CPRLabelTracker:track','No tracker has been trained.');
      end
      
      if isfield(prm.TestInit,'movChunkSize')
        movChunkSize = prm.TestInit.movChunkSize;
      end
                        
      if isempty(tblMFT)
        msgbox('No frames specified for tracking.');
        return;
      end
      tblfldscontainsassert(tblMFT,MFTable.FLDSID);
      assert(isa(tblMFT.mov,'MovieIndex'));
      if any(~tblfldscontains(tblMFT,MFTable.FLDSCORE))
        tblMFT = obj.lObj.labelAddLabelsMFTable(tblMFT);
        tblMFT = obj.lObj.preProcCropLabelsToRoiIfNec(tblMFT);
      end
      if obj.lObj.hasTrx
        tblfldscontainsassert(tblMFT,MFTable.FLDSCOREROI);
      else
        tblfldscontainsassert(tblMFT,MFTable.FLDSCORE);
      end
     
      % if tfWB, then canceling can early-return. In all return cases we
      % want to run hlpTrackWrapupViz.
      oc = onCleanup(@()hlpTrackWrapupViz(obj));
      
      nFrmTrk = size(tblMFT,1);
      iChunkStarts = 1:movChunkSize:nFrmTrk;
      nChunk = numel(iChunkStarts);
      if tfWB && nChunk>1
        wbObj.startPeriod('Tracking chunks','shownumden',true,'denominator',nChunk);
        oc = onCleanup(@()wbObj.endPeriod());
      end
      for iChunk=1:nChunk
        
        if tfWB && nChunk>1
          wbObj.updateFracWithNumDen(iChunk);
        end
        
        idxP0 = (iChunk-1)*movChunkSize+1;
        idxP1 = min(idxP0+movChunkSize-1,nFrmTrk);
        tblMFTChunk = tblMFT(idxP0:idxP1,:);
        fprintf('Tracking frames %d through %d...\n',idxP0,idxP1);
        
        %%% data
        
        if nChunk>1
          % In this case we assume we are dealing with a 'big movie' and
          % don't preserve/cache data
          obj.lObj.preProcInitData();
        end
        
        [d,dIdx] = obj.lObj.preProcDataFetch(tblMFTChunk,'wbObj',wbObj);
        if tfWB && wbObj.isCancel
          % Single-chunk: data unchanged, tracking results unchanged => 
          % obj unchanged.
          %
          % Multi-chunk: data cleared. If 2nd chunk or later, tracking
          % results updated to some extent.
          
          if iChunk>1 % implies nChunk>1
            wbObj.cancelData = struct('msg','Partial tracking results available.');
          end
          return;
        end
        
        d.iTst = dIdx;        
        fprintf(1,'Track data summary:\n');
        d.summarize('mov',d.iTst);
                
        [Is,nChan] = d.getCombinedIsMat(d.iTst);
        prm.Ftr.nChn = nChan;
        
        %% Test on test set; fill/generate pTstT/pTstTRed for this chunk
        NTst = d.NTst;
        RT = prm.TestInit.Nrep;
        nview = obj.sPrm.Model.nviews;
        nfids = prm.Model.nfids;
        assert(nview==numel(obj.trnResRC));
        assert(nview==size(Is.imoffs,2));
        assert(prm.Model.d==2);
        Dfull = nfids*nview*prm.Model.d;
        
        pTstT = nan(NTst,RT,Dfull,prm.Reg.T+1);
        pTstTRed = nan(NTst,Dfull);
        pTstTPruneMD = array2table(nan(NTst,0));
        for iView=1:nview % obj CONST over this loop
          rc = obj.trnResRC(iView);
          %IsVw = Is(:,iView);          
          IsVw = Is;
          IsVw.imszs = IsVw.imszs(:,:,iView);
          IsVw.imoffs = IsVw.imoffs(:,iView);
          bboxesVw = CPRData.getBboxes2D(IsVw);
          if nview==1
            assert(isequal(bboxesVw,d.bboxesTst));
          end
          
          assert(isequal(d.MDTst(:,MFTable.FLDSID),tblMFTChunk(:,MFTable.FLDSID)));
          if tblfldscontains(tblMFTChunk,'thetaTrx')
            oThetas = tblMFTChunk.thetaTrx;
          else
            oThetas = [];
          end
          [p_t,pIidx,p0,p0Info] = rc.propagateRandInit(IsVw,bboxesVw,...
            prm.TestInit,'wbObj',wbObj,'orientationThetas',oThetas);
          if tfWB && wbObj.isCancel
            % obj has CHANGED. If we were really smart, we could use/store
            % partial tracking results in p_t. Or, in practice client can 
            % decrease chunk size as tracking results are saved at those
            % increments.
            % 
            % Single-chunk: .lObj.preProcData updated 
            %
            % Multi-chunk: .lObj.preProcData updated. If 2nd chunk or 
            % later, tracking results updated to some extent.
            
            if iChunk>1 % implies nChunk>1
              wbObj.cancelData = struct('msg','Partial tracking results available.');
            end
            
            return;
          end
          if iChunk==1 && ~isempty(p0DiagImg)
            hFigP0DiagImg = RegressorCascade.createP0DiagImg(IsVw,p0Info);
            [ptmp,ftmp] = fileparts(p0DiagImg);
            p0DiagImgVw = fullfile(ptmp,sprintf('%s_view%d.fig',ftmp,iView));
            savefig(hFigP0DiagImg,p0DiagImgVw);
            delete(hFigP0DiagImg);
          end
          trkMdl = rc.prmModel;
          trkD = trkMdl.D;
          Tp1 = rc.nMajor+1;
          pTstTVw = reshape(p_t,[NTst RT trkD Tp1]);
          
          %% Prune
          [pTstTRedVw,pruneMD] = CPRLabelTracker.applyPruning(...
            pTstTVw(:,:,:,end),d.MDTst(:,MFTable.FLDSID),prm.Prune);
          szassert(pTstTRedVw,[NTst trkD]);
          if nview>1
            pruneMD = tblfldsmodify(pruneMD,@(x)[x '_vw' num2str(iView)]);
          end
          pTstTPruneMD = [pTstTPruneMD pruneMD]; %#ok<AGROW>
                    
          assert(trkD==Dfull/nview);
          assert(mod(trkD,2)==0);
          iFull = (1:nfids)+(iView-1)*nfids;
          iFull = [iFull,iFull+nfids*nview]; %#ok<AGROW>
          pTstT(:,:,iFull,:) = pTstTVw;
          pTstTRed(:,iFull) = pTstTRedVw;       
        end % end obj CONST
        
        fldsTmp = MFTable.FLDSID;
        if tblfldscontains(d.MDTst,'roi')
          fldsTmp{1,end+1} = 'roi'; %#ok<AGROW>
        end
        if tblfldscontains(d.MDTst,'nNborMask')
          fldsTmp{1,end+1} = 'nNborMask'; %#ok<AGROW>
        end
        trkPMDnew = d.MDTst(:,fldsTmp);
        trkPMDnew = [trkPMDnew pTstTPruneMD]; %#ok<AGROW>
        obj.updateTrackRes(trkPMDnew,pTstTRed,pTstT); % XXX out of date api
      end
    end
    
    function track(obj,tblMFT,varargin)
      % tblMFT: MFtable. Req'd flds: MFTable.ID.

            % tblMFT: MFtable. Req'd flds: MFTable.ID.
      
      [movChunkSize,parChunkSize,minChunksPar,useParFor,p0DiagImg,wbObj] = myparse(varargin,...
        'movChunkSize',5000, ... % track large movies in chunks of this size
        'parChunkSize',50, ... % size of batch for each iteration of a parfor loop
        'minChunksPar',2,...
        'useParFor',license('test','distrib_computing_toolbox') && maxNumCompThreads > 1,...
        'p0DiagImg',[], ... % full filename; if supplied, create/save a diagnostic image of initial shapes for first tracked frame
        'wbObj',[] ... % WaitBarWithCancel. If cancel:
                   ... %  1. .lObj.preProcData might be cleared
                   ... %  2. tracking results may be partally updated
        );
      tfWB = ~isempty(wbObj);
      
      prm = obj.sPrm;
      if isempty(prm)
        error('CPRLabelTracker:param','Please specify tracking parameters.');
      end
      if ~all([obj.trnResRC.hasTrained])
        error('CPRLabelTracker:track','No tracker has been trained.');
      end
      
      if isfield(prm.TestInit,'movChunkSize')
        movChunkSize = prm.TestInit.movChunkSize;
      end
      if isfield(prm.TestInit,'parChunkSize')
        parChunkSize = prm.TestInit.parChunkSize;
      end
      if isfield(prm.TestInit,'useParFor')
        useParFor = prm.TestInit.useParFor;
        if ~license('test','distrib_computing_toolbox') || maxNumCompThreads == 1,
          useParFor = false;
        end
      end
      
      fprintf('useParFor = %d\n',useParFor);
      if useParFor,
        fprintf('maxNumCompThreads = %d\n',maxNumCompThreads);
      end
      
      if isempty(tblMFT)
        msgbox('No frames specified for tracking.');
        return;
      end
      tblfldscontainsassert(tblMFT,MFTable.FLDSID);
      assert(isa(tblMFT.mov,'MovieIndex'));
      if any(~tblfldscontains(tblMFT,MFTable.FLDSCORE))
        tblMFT = obj.lObj.labelAddLabelsMFTable(tblMFT);
        tblMFT = obj.lObj.preProcCropLabelsToRoiIfNec(tblMFT);
      end
      if obj.lObj.hasTrx
        tblfldscontainsassert(tblMFT,MFTable.FLDSCOREROI);
      else
        tblfldscontainsassert(tblMFT,MFTable.FLDSCORE);
      end
     
      % if tfWB, then canceling can early-return. In all return cases we
      % want to run hlpTrackWrapupViz.
      oc = onCleanup(@()hlpTrackWrapupViz(obj));
      
      nFrmTrk = size(tblMFT,1);
      iChunkStarts = 1:movChunkSize:nFrmTrk;
      nChunk = numel(iChunkStarts);
      if tfWB && nChunk>1
        wbObj.startPeriod('Tracking chunks','shownumden',true,'denominator',nChunk);
        oc2 = onCleanup(@()wbObj.endPeriod());
      end
      for iChunk=1:nChunk
        
        if tfWB && nChunk>1
          wbObj.updateFracWithNumDen(iChunk);
        end
        
        idxP0 = (iChunk-1)*movChunkSize+1;
        idxP1 = min(idxP0+movChunkSize-1,nFrmTrk);

        % split this into chunks of size parChunkSize
        nFramesCurr = idxP1-idxP0+1;
        nParChunks = max(1,round(nFramesCurr/parChunkSize));
        chunkStarts = round(linspace(1,nFramesCurr+1,nParChunks+1));
        chunkEnds = chunkStarts(2:end)-1;
        tblMFTChunk = tblMFT(idxP0:idxP1,:);
        fprintf('Tracking frames %d through %d...\n',idxP0,idxP1);
        
        %%% data
        
        if nChunk>1
          % In this case we assume we are dealing with a 'big movie' and
          % don't preserve/cache data
          obj.lObj.preProcInitData();
        end
        
        [d,dIdx] = obj.lObj.preProcDataFetch(tblMFTChunk,'wbObj',wbObj);
        if tfWB && wbObj.isCancel
          % Single-chunk: data unchanged, tracking results unchanged => 
          % obj unchanged.
          %
          % Multi-chunk: data cleared. If 2nd chunk or later, tracking
          % results updated to some extent.
          
          if iChunk>1 % implies nChunk>1
            wbObj.cancelData = struct('msg','Partial tracking results available.');
          end
          return;
        end
        
        d.iTst = dIdx;        
        fprintf(1,'Track data summary:\n');
        d.summarize('mov',d.iTst);
                
        [Is,nChan] = d.getCombinedIsMat(d.iTst);
        prm.Ftr.nChn = nChan;
        
        %% Test on test set; fill/generate pTstT/pTstTRed for this chunk
        NTst = d.NTst;
        RT = prm.TestInit.Nrep;
        nview = obj.sPrm.Model.nviews;
        nfids = prm.Model.nfids;
        assert(nview==numel(obj.trnResRC));
        assert(nview==size(Is.imoffs,2));
        assert(prm.Model.d==2);
        Dfull = nfids*nview*prm.Model.d;
        
        pTstT = nan(NTst,RT,Dfull,prm.Reg.T+1);
        pTstTRed = nan(NTst,Dfull);
        pTstTPruneMD = array2table(nan(NTst,0));
        TestInit = prm.TestInit;
        pTstTTrnTS = nan(1,nview);
        for iView=1:nview % obj CONST over this loop
          rc = obj.trnResRC(iView);
          %IsVw = Is(:,iView);          

%           if nview==1
%             assert(isequal(bboxesVw,d.bboxesTst));
%           end
          
          assert(isequal(d.MDTst(:,MFTable.FLDSID),tblMFTChunk(:,MFTable.FLDSID)));
          if tblfldscontains(tblMFTChunk,'thetaTrx')
            istheta = true;
            oThetas = tblMFTChunk.thetaTrx;
          else
            istheta = false;
            oThetas = [];
          end
          
          if useParFor && nParChunks >= minChunksPar,
            tic;
            p_t = cell(nParChunks,1);
            parfor jChunk = 1:nParChunks,
              i0 = chunkStarts(jChunk);
              i1 = chunkEnds(jChunk);
              nFramesCurr = i1-i0+1;
              
              IsVw = Is;
              IsVw.imszs = IsVw.imszs(:,i0:i1,iView);
              IsVw.imoffs = IsVw.imoffs(i0:i1,iView);
              bboxesVw = CPRData.getBboxes2D(IsVw);
              if istheta,
                oThetasChunk = oThetas(i0:i1);
              else
                oThetasChunk = [];
              end
              
              [p_t{jChunk}] = rc.propagateRandInit(IsVw,bboxesVw,...
                TestInit,'orientationThetas',oThetasChunk);
              
              % restarts get intermixed with examples, separate before
              % concatenating
              sz = size(p_t{jChunk});
              sz(1) = sz(1) / nFramesCurr;
              p_t{jChunk} = reshape(p_t{jChunk},[nFramesCurr,sz]);
              
            end
            
            % remix restarts
            p_t = cell2mat(p_t);
            sz = size(p_t);
            p_t = reshape(p_t,[sz(1)*sz(2),sz(3:end)]);
            toc;
          else
            
            IsVw = Is;
            IsVw.imszs = IsVw.imszs(:,:,iView);
            IsVw.imoffs = IsVw.imoffs(:,iView);
            bboxesVw = CPRData.getBboxes2D(IsVw);
            [p_t] = rc.propagateRandInit(IsVw,bboxesVw,...
              prm.TestInit,'wbObj',wbObj,'orientationThetas',oThetas);
          end
          
          if tfWB && wbObj.isCancel
            % obj has CHANGED. If we were really smart, we could use/store
            % partial tracking results in p_t. Or, in practice client can 
            % decrease chunk size as tracking results are saved at those
            % increments.
            % 
            % Single-chunk: .lObj.preProcData updated 
            %
            % Multi-chunk: .lObj.preProcData updated. If 2nd chunk or 
            % later, tracking results updated to some extent.
            
            if iChunk>1 % implies nChunk>1
              wbObj.cancelData = struct('msg','Partial tracking results available.');
            end
            
            return;
          end
          if iChunk==1 && ~isempty(p0DiagImg)
            
            IsVw = Is;
            IsVw.imszs = IsVw.imszs(:,1,iView);
            IsVw.imoffs = IsVw.imoffs(1,iView);
            bboxesVw = CPRData.getBboxes2D(IsVw);
            oThetasChunk = oThetas(1);
            [~,~,~,p0Info] = rc.propagateRandInit(IsVw,bboxesVw,...
              TestInit,'orientationThetas',oThetasChunk);
            
            hFigP0DiagImg = RegressorCascade.createP0DiagImg(IsVw,p0Info);
            [ptmp,ftmp] = fileparts(p0DiagImg);
            p0DiagImgVw = fullfile(ptmp,sprintf('%s_view%d.fig',ftmp,iView));
            savefig(hFigP0DiagImg,p0DiagImgVw);
            delete(hFigP0DiagImg);
          end
          trkMdl = rc.prmModel;
          trkD = trkMdl.D;
          Tp1 = rc.nMajor+1;
          pTstTVw = reshape(p_t,[NTst RT trkD Tp1]);
          
          %% Prune
          [pTstTRedVw,pruneMD] = CPRLabelTracker.applyPruning(...
            pTstTVw(:,:,:,end),d.MDTst(:,MFTable.FLDSID),prm.Prune);
          szassert(pTstTRedVw,[NTst trkD]);
          if nview>1
            pruneMD = tblfldsmodify(pruneMD,@(x)[x '_vw' num2str(iView)]);
          end
          pTstTPruneMD = [pTstTPruneMD pruneMD]; %#ok<AGROW>
                    
          assert(trkD==Dfull/nview);
          assert(mod(trkD,2)==0);
          iFull = (1:nfids)+(iView-1)*nfids;
          iFull = [iFull,iFull+nfids*nview]; %#ok<AGROW>
          pTstT(:,:,iFull,:) = pTstTVw;
          pTstTRed(:,iFull) = pTstTRedVw; 
          
          pTstTTrnTS(iView) = rc.trnLog(end).ts;
        end % end obj CONST
        
        fldsTmp = MFTable.FLDSID;
        if tblfldscontains(d.MDTst,'roi')
          fldsTmp{1,end+1} = 'roi'; %#ok<AGROW>
        end
        if tblfldscontains(d.MDTst,'nNborMask')
          fldsTmp{1,end+1} = 'nNborMask'; %#ok<AGROW>
        end
        trkPMDnew = d.MDTst(:,fldsTmp);
        trkPMDnew = [trkPMDnew pTstTPruneMD]; %#ok<AGROW>
        obj.updateTrackRes(trkPMDnew,pTstTRed,pTstT,pTstTTrnTS);
      end
      
    end
      
    function hlpTrackWrapupViz(obj)
      if ~isempty(obj.lObj)
        obj.vizLoadXYPrdCurrMovieTarget();
        obj.newLabelerFrame();
        notify(obj,'newTrackingResults');
      end
    end

    %MTGT
    %#%MV
    function [trkfiles,tfHasRes] = getTrackingResults(obj,mIdx)
      % Get tracking results for movie(set) iMov.
      %
      % mIdx: [nMov] MovieIndex vector
      %
      % trkfiles: [nMovxnView] TrkFile objects
      % tfHasRes: [nMov] logical. If true, corresponding movie has tracking
      %   nontrivial (nonempty) tracking results
      
      assert(isvector(mIdx) && isa(mIdx,'MovieIndex'));

      if isempty(obj.trkPTS)
        error('CPRLabelTracker:noRes','No current tracking results.');
      end
      
      nMov = numel(mIdx);
      trkpipt = obj.trkPiPt;
      trkinfobase = struct('param',obj.sPrm);
      
      tfMultiView = obj.lObj.isMultiView;
      if tfMultiView
        nPhysPts = obj.lObj.nPhysPoints;
        nview = obj.lObj.nview;
        assert(isequal(trkpipt,1:nPhysPts*nview));
        ipt2vw = meshgrid(1:nview,1:nPhysPts);
        assert(isequal(obj.lObj.labeledposIPt2View,ipt2vw(:)));
      end
        
      for i = nMov:-1:1
        [trkpos,trkposTS,trkposFull,trkposFullMFT,trkposTrnTS,tfHasRes(i)] = ...
                                        obj.getTrackResRaw(mIdx(i));
        if tfMultiView
          assert(size(trkpos,1)==nPhysPts*nview);
          assert(numel(trkposTrnTS)==nview);
          for ivw=nview:-1:1
            iptCurrVw = (1:nPhysPts) + (ivw-1)*nPhysPts;
            trkinfo = trkinfobase;
            trkinfo.view = ivw;
            trkinfo.trnTS = trkposTrnTS(ivw);
            trkfiles(i,ivw) = TrkFile(trkpos(iptCurrVw,:,:,:),...
              'pTrkTS',trkposTS(iptCurrVw,:,:),...
              'pTrkiPt',1:nPhysPts,...
              'pTrkFull',trkposFull(iptCurrVw,:,:,:),...
              'pTrkFullFT',trkposFullMFT(:,{'frm' 'iTgt'}),...
              'trkInfo',trkinfo);
          end
        else
          trkinfo = trkinfobase;
          trkinfo.trnTS = trkposTrnTS;
          trkfiles(i,1) = TrkFile(trkpos,...
            'pTrkTS',trkposTS,...
            'pTrkiPt',trkpipt,...
            'pTrkFull',trkposFull,...
            'pTrkFullFT',trkposFullMFT(:,{'frm' 'iTgt'}),...
            'trkInfo',trkinfo);
        end
      end
    end
    
    function s = getTrainedTrackerMetadata(obj)      
      s = getTrainedTrackerMetadata@LabelTracker(obj);
      s.param = obj.sPrm;
      s.trkPTrnTS = obj.trkPTrnTS;
    end

    % TODO AL20170406.
    % This is in approximate shape, started fixing with issue #77 but
    % realized no clients. 
    % Size-check TrkFile.pTrk, .pTrkFull, .pTrkFrm, .pTrkiPt. This isn't
    % careful and assumes dimensions (nframes, trkiPt etc) all match.
    
%     function importTrackingResults(obj,iMovs,trkfiles)
%       % Any existing tracking results in iMovs are OVERWRITTEN even if the
%       % tracking results in trkfiles are all NaNs
%       
%       lObj = obj.lObj;
%       
%       if lObj.isMultiView
%         error('CPRLabelTracker:mv','Unsupported for multiview projects.');
%       end
%       
%       validateattributes(iMovs,{'numeric'},...
%         {'positive' 'integer' '<=' lObj.nmovies});
%       nMovs = numel(iMovs);
%       assert(isa(trkfiles,'TrkFile') && numel(trkfiles)==nMovs);
% 
%       prmFile0 = obj.paramFile;
%       
%       for i = 1:nMovs
%         iMv = iMovs(i);
%         tfile = trkfiles(i);
%         movFileID = FSPath.standardPath(lObj.movieFilesAll{iMv});
%         movFileFull = lObj.movieFilesAllFull{iMv};
% 
%         prmFile1 = tfile.trkInfo.paramFile;
%         if ~isempty(prmFile0) && ~isempty(prmFile1) && ~strcmp(prmFile0,prmFile1)
%           warningNoTrace('CPRLabelTracker:paramFile',...
%             'Tracking results generated using parameter file ''%s'', which differs from current file ''%s''.',...
%             prmFile1,prmFile0);
%         end
%         % Note, we do not force the prmFiles to agree. And maybe in some
%         % weird cases, one or both are empty.
%         
%         nfrm = lObj.movieInfoAll{iMv}.nframes;
%         if size(tfile.pTrk,3)~=nfrm
%           error('CPRLabelTracker:importTrackingResults',...
%             'Trkfile inconsistent with number of frames in movie %s.',movFileFull);
%         end
%                 
%         % find and clear all tracking results for this mov
%         tfCurrMov = strcmp(obj.trkPMD.mov,movFileID);
%         if any(tfCurrMov)
%           warningNoTrace('CPRLabelTracker:importTrackingResults',...
%             'Clearing %d frames of existing tracking results for movie %s.',...
%             nnz(tfCurrMov),movFileID);
%           obj.trkP(tfCurrMov,:) = [];
%           if ~isempty(obj.trkPFull)
%             assert(size(obj.trkPFull,1)==numel(tfCurrMov));
%             obj.trkPFull(tfCurrMov,:,:,:) = [];
%           end
%           obj.trkPTS(tfCurrMov,:) = [];
%           obj.trkPMD(tfCurrMov,:) = [];
%         end
%         
%         % load tracking results for this mov
%         
%         % find frames that have at least one non-nan point
%         
%         d = 2;
%         trkD = d*obj.nPtsTrk;
%         tmptrkP = reshape(tfile.pTrk,trkD,nfrm)'; % [nfrm x trkD]
%         if obj.storeFullTracking
%           if isempty(tfile.pTrkFull) % could be eg [npttrked x 2 x nRep=0 x nfrm]
%             warning('CPRLabelTracker:trkPFull',...
%               'TrkFile field .pTrkFull is empty. Full tracking results will be unavailable for movie movFileFull.');
%             tmptrkPfull = nan(xxx,xxxx);
%           elseif 
%             el
%           tmptrkPfull = reshape(
%         end
%         tfNotNanFrm = any(~isnan(tmptrkP),2);
%         nRowsToAdd = nnz(tfNotNanFrm);
%         
%         if nRowsToAdd>0
%           if isempty(obj.trkPiPt)
%             assert(isempty(obj.trkP));
%             obj.trkPiPt = tfile.pTrkiPt;
%           end
%           if ~isequal(obj.trkPiPt,tfile.pTrkiPt)
%             error('CPRLabelTracker:trkPiPt',...
%               'Movie %s: ''trkPiPt'' differs in tracked results to be loaded.',...
%               movFileFull);
%           end        
% 
%           TRKMDVARNAMES = {'mov' 'frm'};
%           assert(strcmp(obj.trkPMD.Properties.VariableNames,TRKMDVARNAMES));
% 
%           % OK: update .trkP, trkPFull, trkPMD, trkPTS
%           obj.trkP = cat(1,obj.trkP,tmptrkP(tfNotNanFrm,:));
%           if obj.storeFullTracking
%             obj.trkPFull = cat(1,obj.trkPFull,...
%               nan(nRowsToAdd,size(obj.trkPFull,2),trkD,size(obj.trkPFull,4)));
%           end
%           mdMov = repmat({movFileID},nRowsToAdd,1);
%           mdFrm = find(tfNotNanFrm);
%           mdFrm = mdFrm(:);
%           mdNew = table(mdMov,mdFrm,'VariableNames',TRKMDVARNAMES);
%           obj.trkPMD = cat(1,obj.trkPMD,mdNew);
%           tsNew = tfile.pTrkTS(:,tfNotNanFrm);
%           tsNew = max(tsNew,1)';
%           obj.trkPTS = cat(1,obj.trkPTS,tsNew);
% 
%           % tfile.pTrkTag is ignored
%           tftmp = ~cellfun(@isempty,tfile.pTrkTag);
%           if any(tftmp(:))
%             warningNoTrace('CPRLabelTracker:importTrackingResults',...
%               'Movie %s: Ignoring nontrivial .pTrkTag field in TrkFile.',movFileFull);
%           end
%           
%           fprintf(1,'Movie %s: loaded %d frames of tracking results.\n',...
%             movFileFull,nRowsToAdd);
%         end
%         
%         assert(isequal(size(obj.trkP,1),size(obj.trkPMD,1),size(obj.trkPTS,1)));
%         if obj.storeFullTracking
%           assert(size(obj.trkP,1)==size(obj.trkPFull,1));
%         end
%       end
%       fprintf(1,'Loaded tracking results for %d movies.\n',nMovs);
%     end
    
    function clearTrackingResults(obj)
      %obj.initData();
      obj.trackResInit();
      obj.vizLoadXYPrdCurrMovieTarget();
      obj.newLabelerFrame();
      % Don't asyncReset() here
      notify(obj,'newTrackingResults');
    end
    
    %#%MTGT
    function newLabelerFrame(obj)
      % Update .hXYPrdRed based on current Labeler frame and .xyPrdCurrMovie

      if obj.lObj.isinit || ~obj.lObj.hasMovie
        return;
      end
      
      [xy,isinterp,xyfull] = obj.getPredictionCurrentFrame();
    
      if obj.asyncPredictOn && all(isnan(xy(:)))
        obj.asyncTrackCurrFrameBG();
      end
      
      if isinterp
        plotargs = obj.xyVizPlotArgsInterp;
      else
        plotargs = obj.xyVizPlotArgs;
      end
      
      npts = obj.nPts;
      %ntgt = obj.lObj.nTargets;
      itgt = obj.lObj.currTarget;
      hXY = obj.hXYPrdRed;
      for iPt=1:npts
        set(hXY(iPt),'XData',xy(iPt,1,itgt),'YData',xy(iPt,2,itgt),plotargs{:});
      end
      
      if obj.showVizReplicates && ...
         obj.storeFullTracking~=StoreFullTrackingType.NONE && ...
         ~isequal(xyfull,[])
        
        hXY = obj.hXYPrdFull;
        plotargs = obj.xyVizFullPlotArgs;
        for iPt = 1:npts
          set(hXY(iPt),'XData',xyfull(iPt,1,:),'YData',xyfull(iPt,2,:),plotargs{:});
        end       
      end 
    end
    
    function newLabelerTarget(obj)
      if obj.lObj.isinit
        return;
      end
      if obj.storeFullTracking~=StoreFullTrackingType.NONE
        obj.vizLoadXYPrdCurrMovieTarget(); % needed to reload full tracking results
      end
      obj.newLabelerFrame();
    end
    
    function newLabelerMovie(obj)
      obj.vizInit();
      if obj.lObj.hasMovie
        obj.vizLoadXYPrdCurrMovieTarget();
        obj.newLabelerFrame();
      end
    end
    
    function labelerMovieRemoved(obj,eventdata)
      mIdxOrig2New = eventdata.mIdxOrig2New;
      keys = cell2mat(mIdxOrig2New.keys);
      vals = cell2mat(mIdxOrig2New.values);
      szassert(keys,size(vals));
      mIdx = keys(vals==0);
      mIdx = MovieIndex(mIdx);
      assert(isscalar(mIdx)); % for now
      
%       % .data*. Remove any removed movies from .data cache, relabel MD.mov
%       obj.data.movieRemap(mIdxOrig2New);
%     AL: Now done in Labeler
      
      % trnData*. If a movie is being removed that is in trnDataTblP, to be 
      % safe we invalidate any trained tracker and tracking results.
      tfRm = obj.trnDataTblP.mov==mIdx;
      if any(tfRm)
        if isdeployed
          error('CPRLabelTracker:movieRemoved',...
            'Unexpected codepath for deployed APT.');
        else
          resp = questdlg('A movie present in the training data has been removed. Any trained tracker and tracking results will be cleared.',...
            'Training row removed',...
            'OK','(Dangerous) Do not clear tracker/tracking results','OK');
          if isempty(resp)
            resp = 'OK';
          end
          switch resp
            case 'OK'
              obj.trnDataInit();
              obj.trnResInit();
              obj.trackResInit();
              obj.vizInit();
              obj.asyncReset();
            case '(Dangerous) Do not clear tracker/tracking results'
              obj.trnDataInit();
              % trnRes not cleared
              % trackRes not cleared
            otherwise
              assert(false);
          end
        end
      else
        % .trnDataTblP does not contain a movie-being-removed, but we still
        % need to relabel movie indices.
        obj.trnDataTblP = MFTable.remapIntegerKey(obj.trnDataTblP,'mov',...
          mIdxOrig2New);
        assert(~any(obj.trnDataTblP.mov==0));
      end
      
      % trkP*. Relabel .mov in tables; remove any removed movies from 
      % tracking results. 
      [obj.trkPMD,tfRm] = MFTable.remapIntegerKey(obj.trkPMD,'mov',...
        mIdxOrig2New);
      obj.trkP(tfRm,:) = [];
      if ~isequal(obj.trkPFull,[])
        obj.trkPFull(tfRm,:,:,:) = []; % Should work fine even when .storeFullTracking is .FINALITER and .trkPFull has 3 dims
      end
      obj.trkPTS(tfRm,:) = [];
      
%       obj.vizLoadXYPrdCurrMovieTarget();
%       obj.newLabelerFrame();
    end
    
    function labelerMoviesReordered(obj,eventdata)
      mIdxOrig2New = eventdata.mIdxOrig2New;
      vals = cell2mat(mIdxOrig2New.values);
      assert(~any(vals==0),'Unexpected movie removal.');
      
%       obj.data.movieRemap(mIdxOrig2New); AL now done in Labeler
      obj.trnDataTblP = MFTable.remapIntegerKey(obj.trnDataTblP,'mov',...
        mIdxOrig2New);
      obj.trkPMD = MFTable.remapIntegerKey(obj.trkPMD,'mov',mIdxOrig2New);
    end
    
    function s = getSaveToken(obj)
      % See save philosophy below. ATM we return a "full" struct with
      % 2+3+4;
      
      s1 = obj.getTrainedTrackerSaveStruct();
      s2 = obj.getTrackResSaveStruct();
      assert(isequal(s1.paramFile,s2.paramFile));
      s2 = rmfield(s2,'paramFile');
      s = structmerge(s1,s2);
      s.hideViz = obj.hideViz;
    end
    
    function loadSaveToken(obj,s)
      % Currently we only call this on new/initted trackers.

      obj.asyncReset();
      
      %%% BEGIN MODERNIZE s
      
      if isfield(s,'labelTrackerClass')
        s = rmfield(s,'labelTrackerClass'); % legacy
      end            
     
      % modernize params
      if isfield(s,'sPrm') && ~isempty(s.sPrm)
        s.sPrm = CPRLabelTracker.modernizeParams(s.sPrm);       
        
        % 20161017
        % changes to default params param.example.yaml:
        % - Model:nviews now necessary and defaults to 1
        % - TrainInit:augjitterfac, default val 16
        % - TestInit:augjitterfac, default val 16
        %
        % A bit of a bind here b/c some parameter state is dup-ed in
        % RegressorCascade; we do not want to reinit RegressorCascade 
        % (.trnResRC) for legacy projs, because legacy projs implicitly 
        % used all the above "new" parameters and so re-init is not 
        % necessary. See hack below.
        %
        % 20170531 
        % Considered making RegressorCascade.prm* handle objects rather
        % than structs. Considered either hardcoded handle objects or 
        % dynamicprops "handle structs". RegressorCascade has a copy of a 
        % subset of parameters b/c it is standalone-functional (eg without
        % APT or CPRLabelTracker). So using some kind handle struct shared 
        % with CPRLabelTracker would be most natural.
        %
        % The downsides of using a handle struct are i) maintenance and ii)
        % (prob very minor) performance. Maintenance is the bigger issue,
        % the up-to-date parameters with defaults are already provided in
        % the param.example.yaml and a separate structure would require a
        % double-update (unless using dynamicprops which is 10x slower than
        % a struct).
                
        % Hack, double-update legacy RegressorCascades (.trnResRC).
        rc = s.trnResRC;
        if ~isempty(rc) && isscalar(rc) 
          % 20161128: multiview projs (nonscalar rc) should not require
          % these updates.
          
          assert(isa(rc,'RegressorCascade')); % handle obj
          if isempty(rc.prmModel.nviews)
            assert(s.sPrm.Model.nviews==1); 
            rc.prmModel.nviews = 1;
          end
          if ~isfield(rc.prmTrainInit,'augjitterfac')
            assert(s.sPrm.TrainInit.augjitterfac==16);
            rc.prmTrainInit.augjitterfac = 16;
          end
        end

        for i=1:numel(rc)
          % 20170531 legacy projs prm.Reg.USE_AL_CORRECTION
          if isfield(rc(i).prmReg,'USE_AL_CORRECTION')
            rc(i).prmReg = s.sPrm.Reg;
          end
          
          % 20170609 iss84
          rc(i).prmTrainInit.augrotate = [];
          
          % 20180326 Feature type: '1lm'->'single landmark'
          % (s.sPrm updated above, this is a double-update)
          if strcmp(rc(i).prmFtr.type,'1lm')
            rc(i).prmFtr.type = 'single landmark';            
          end
          for iSpec=1:numel(rc(i).ftrSpecs)
            if ~isempty(rc(i).ftrSpecs{iSpec}) && strcmp(rc(i).ftrSpecs{iSpec}.type,'1lm')
              rc(i).ftrSpecs{iSpec}.type = 'single landmark';
            end
          end
        end
      else
        assert(isempty(s.trnResRC));
      end
      
      %%% 20161031 modernize tables: .trnDataTblP, .trkPMD
      % 20170531 add .iTgt to tables
      % remove .movS field
      if isempty(s.trnDataTblP)
        % just re-init table
        s.trnDataTblP  = MFTable.emptyTable(MFTable.FLDSFULL);
      else
        s.trnDataTblP = MFTable.rmMovS(s.trnDataTblP);
        if ~tblfldscontains(s.trnDataTblP,'iTgt')
          s.trnDataTblP.iTgt = ones(height(s.trnDataTblP),1);
        end
      end
      if isempty(s.trkPMD)
        s.trkPMD = MFTable.emptyTable(MFTable.FLDSID);
      else
        s.trkPMD = MFTable.rmMovS(s.trkPMD);
        if ~tblfldscontains(s.trkPMD,'iTgt')
          s.trkPMD.iTgt = ones(height(s.trkPMD),1);
        end
      end
      
      % 20170831. Any project with non-trivial GT mode should have already 
      % converted (if necessary) all char movieIDs in MD tables to 
      % movieIdxs.
      if obj.lObj.nmoviesGT>0
        assert(~iscellstr(s.trnDataTblP.mov));
        assert(~iscellstr(s.trkPMD.mov));
      end
      
      allProjMovIDs = FSPath.standardPath(obj.lObj.movieFilesAll);
      allProjMovsFull = obj.lObj.movieFilesAllFull;
      if obj.lObj.isMultiView
        nrow = size(allProjMovIDs,1);
        tmpIDs = cell(nrow,1);
        tmpFull = cell(nrow,1);
        for i=1:nrow
          % 20180611 allProjMovIDs/Full only used for very old legacy 
          % projects. Don't worry about ID separator issue.
          tmpIDs{i} = MFTable.formMultiMovieID(allProjMovIDs(i,:));
          tmpFull{i} = MFTable.formMultiMovieID(allProjMovsFull(i,:));
        end
        allProjMovIDs = tmpIDs;
        allProjMovsFull = tmpFull;
      end
      % 20161128. Multiview tracking is being put in after the transition
      % to using movieIDs in all tables, so the replaceMovieFullWithMovieID
      % business in the following should be no-ops for multiview projects.
      if ~isempty(s.trnDataTblP)
        tblDesc = 'Training data';
        if iscellstr(s.trnDataTblP.mov)
          s.trnDataTblP = MFTable.replaceMovieStrWithMovieIdx(s.trnDataTblP,...
            allProjMovIDs,allProjMovsFull,tblDesc);
          if any(s.trnDataTblP.mov==0)
            warndlg('One or more training rows in this project contain an unrecognized movie. This can occur when movies are moved or removed. Retraining your project is recommended.',...
              'Unrecognized movie');
          end
        end
        MFTable.warnDupMovFrmKey(s.trnDataTblP,tblDesc);
      end
      if ~isempty(s.trkPMD)
        tblDesc = 'Tracking results';
        if iscellstr(s.trkPMD.mov)
          s.trkPMD = MFTable.replaceMovieStrWithMovieIdx(s.trkPMD,...
            allProjMovIDs,allProjMovsFull,tblDesc);
          if any(s.trkPMD.mov==0)
            warningNoTrace('CPRLabelTracker:mov',...
              'One or more tracking result rows in this project contain an unrecognized movie. This can occur when movies in a project are moved or removed. These tracking results will be ignored.',...
              'Unrecognized tracking results');
          end
        end
        MFTable.warnDupMovFrmKey(s.trkPMD,tblDesc);
      end
      
      % 20170405. trnDataDownSamp
      if ~isfield(s,'trnDataDownSamp')
        s.trnDataDownSamp = false;
      end
      
      % 20170406. Reduce .trkP
      if ~isempty(s.trkP)
        % Go from [ntrkfrm x D x Tp1] -> [ntrkfrm x D]
        s.trkP = s.trkP(:,:,end);
      end
      
      % 20170407: storeFullTracking, showVizReplicates
      if ~isfield(s,'storeFullTracking')
        s.storeFullTracking = false;
      end
      if ~isfield(s,'showVizReplicates')
        s.showVizReplicates = false;
      end
      
      % 20170823
      if ~isfield(s,'hideViz')
        s.hideViz = false;
      end
      
      % 20170926
      if ~isa(s.trnDataTblP.mov,'MovieIndex')
        s.trnDataTblP.mov = MovieIndex(s.trnDataTblP.mov);
      end
      if ~isa(s.trkPMD.mov,'MovieIndex')
        s.trkPMD.mov = MovieIndex(s.trkPMD.mov);
      end

      % 20171114
      if ~isempty(s.trkPMD) && ~tblfldscontains(s.trkPMD,'nNborMask')
        nNborMask = nan(height(s.trkPMD),1);
        s.trkPMD = [s.trkPMD table(nNborMask)];
      end
      
      % 20171212: storeFullTracking
      if islogical(s.storeFullTracking)
        if s.storeFullTracking
          s.storeFullTracking = StoreFullTrackingType.ALLITERS;
        else
          s.storeFullTracking = StoreFullTrackingType.NONE;
        end
      end
      assert(isa(s.storeFullTracking,'StoreFullTrackingType'));
      
      % 20180310
      if isfield(s,'trnResH0')
        if ~isempty(s.trnResH0)
          warningNoTrace('Clearing legacy histogram equalization information found in tracker.');
        end
        s = rmfield(s,'trnResH0');
      end      
      
      % 20180502
      if ~isfield(s,'trkPTrnTS')
        s.trkPTrnTS = nan(1,obj.lObj.nview);
      end

      %%% END MODERNIZE S

      % set parameter struct s.sPrm on obj
      assert(isempty(obj.sPrm)); % Currently this is only called on a freshly-created CPRLT obj
      obj.sPrm = s.sPrm;    
%       if ~isequaln(obj.sPrm,s.sPrm)
%       warningNoTrace('CPRLabelTracker:param',...
%         'CPR tracking parameters changed to saved values.');
%       end
%       obj.setParamContentsSmart(s.sPrm);
     
      % set everything else. Note this should set all core CPRLT state (not
      % viz, volatile, etc)
      flds = fieldnames(s);
      flds = setdiff(flds,{'sPrm' 'hideViz'});
      obj.isInit = true;
      try
        for f=flds(:)',f=f{1}; %#ok<FXSET>
          obj.(f) = s.(f);
        end
      catch ME
        obj.isInit = false;
        ME.rethrow();
      end
      obj.isInit = false;
      
      obj.setHideViz(s.hideViz);
      obj.vizLoadXYPrdCurrMovieTarget();
      obj.newLabelerFrame();
    end
    
    %#%MTGT
    function [xy,isinterp,xyfull] = getPredictionCurrentFrame(obj)
      % xy: [nPtsx2xnTgt], tracking results for all targets in current frm
      % isinterp: scalar logical, only relevant if nTgt==1
      % xyfull: [nPtsx2xnRep]. full tracking only for current target. Only 
      %   available if .storeFullTracking is not .NONE
      
      frm = obj.lObj.currFrame;
      xyPCM = obj.xyPrdCurrMovie;
      if isempty(xyPCM)
        npts = obj.nPts;
        nTgt = obj.lObj.nTargets;
        xy = nan(npts,2,nTgt);
        isinterp = false;
      else
        % AL20160502: When changing movies, order of updates to 
        % lObj.currMovie and lObj.currFrame is unspecified. currMovie can
        % be updated first, resulting in an OOB currFrame; protect against
        % this.
        frm = min(frm,size(xyPCM,3));
        
        xy = squeeze(xyPCM(:,:,frm,:)); % [npt x d x ntgt]
        isinterp = obj.xyPrdCurrMovieIsInterp(frm);
      end
      if obj.storeFullTracking>StoreFullTrackingType.NONE && ...
          ~isequal(obj.xyPrdCurrMovieFull,[])
        % frm should have gone through 'else' branch above and should be
        % in-range for .xyPrdMovieFull
        
        xyfull = obj.xyPrdCurrMovieFull(:,:,:,frm);
      else
        xyfull = [];
      end
    end
    
    function props = propList(obj)
      % Return a list of properties that could be shown in the
      % infotimeline
      props = {'x' 'y' 'dx' 'dy' '|dx|' '|dy|'}';
    end
    
    function data = getPropValues(obj,pcode)
      % Return the values of a particular property for
      % infotimeline
      
      labeler = obj.lObj;
      npts = labeler.nLabelPoints;
      nfrms = labeler.nframes;
      ntgts = labeler.nTargets;
      iTgt = labeler.currTarget;
      tpos = obj.xyPrdCurrMovie; % "trked pos" ala lpos
      if isempty(tpos)
        % edge case uninitted (not sure why)
        tpos = nan(npts,2,nfrms,ntgts);
      end
      tpostag = cell(npts,nfrms,ntgts);
      data = InfoTimeline.getDataFromLpos(tpos,tpostag,pcode,iTgt);
    end
       
  end
    
  %% Save, Load, Init etc
  % The serialization philosophy is as follows.
  %
  % At a high level there are four groups of state forming a linear
  % dependency chain (basically)
  % 0. sPrm: all state is dependent on parameters.
  % 1. .lObj.preProcData, .preProcDataTS.
  % 2. Training Data specification: .trnData*
  % 3. Training results (trained tracker): .trnRes*
  % 4: Tracking results: .trkP*
  %
  % - The data in 1) is usually large. ATM we do not save it.
  % - You might want to save just 2., but much more commonly you will want
  % to save 2+3. If you want to save 3, it really makes sense to save 2 as
  % well. So we support saving 2+3. This is saving/loading a "trained 
  % tracker".
  % - You might want to save 4. You might want to do this independent of
  % 2+3. So we support saving 4 orthogonally, although of course sometimes 
  % you will want to save everything.
  %
  methods
        
    function s = getTrainedTrackerSaveStruct(obj)
      s = struct();
      props = obj.TRAINEDTRACKER_SAVEPROPS;
      s.paramFile = obj.paramFile;
      for p=props(:)',p=p{1}; %#ok<FXSET>
        s.(p) = obj.(p);
      end
    end
    
    function s = getTrackResSaveStruct(obj)
      s = struct();
      s.paramFile = obj.paramFile;
      props = obj.TRACKRES_SAVEPROPS;
      for p=props(:)',p=p{1}; %#ok<FXSET>
        s.(p) = obj.(p);
      end
    end
    
%     function loadTrainedTrackerSaveStruct(obj,s)
%       if ~isempty(obj.paramFile) && ~isequal(s.paramFile,obj.paramFile)
%         warningNoTrace('CPRLabelTracker:paramFile',...
%           'Tracker trained using parameter file ''%s'', which differs from current file ''%s''.',...
%           s.paramFile,obj.paramFile);
%       end      
%       
%       obj.paramFile = s.paramFile;
%       props = obj.TRAINEDTRACKER_SAVEPROPS;
%       for p=props(:)',p=p{1}; %#ok<FXSET>
%         obj.(p) = s.(p);
%       end
%     end
    
%     function saveTrainedTracker(obj,fname)
%       s = obj.getTrainedTrackerSaveStruct(); %#ok<NASGU>
%       save(fname,'-mat','-struct','s');
%     end
    
%     function loadTrainedTracker(obj,fname)
%       s = load(fname,'-mat');
%       obj.loadTrainedTrackerSaveStruct(s);
%     end
        
%     function loadTrackResSaveStruct(obj,s)
%       if ~isempty(obj.paramFile) && ~isequal(s.paramFile,obj.paramFile)
%         warningNoTrace('CPRLabelTracker:paramFile',...
%           'Results tracked using parameter file ''%s'', which differs from current file ''%s''.',...
%           s.paramFile,obj.paramFile);
%       end
%       obj.paramFile = s.paramFile;
%       props = obj.TRACKRES_SAVEPROPS;
%       for p=props(:)',p=p{1}; %#ok<FXSET>
%         obj.(p) = s.(p);
%       end
%     end
    
%     function saveTrackRes(obj,fname)
%       s = obj.getTrackResSaveStruct(); %#ok<NASGU>
%       save(fname,'-mat','-struct','s');
%     end
    
    function trackResInit(obj)
      % init obj.TRACKRES_SAVEPROPS
      
      obj.trkP = [];
      obj.trkPFull = [];
      obj.trkPTS = zeros(0,1);
      obj.trkPTrnTS = nan(1,obj.lObj.nview);
      % wrong fields but will get overwritten. 20170531 why not use right fields?
      obj.trkPMD = MFTable.emptyTable(MFTable.FLDSID);
      obj.trkPiPt = [];
    end
    
  end
  
  %% Async -- Background tracking
  
  methods
    
    function asyncReset(obj,tfwarn)
      % Clear all async* state
      %
      % See asyncDetachedCopy for the state copied onto the BG worker. The
      % BG worker depends on: .sPrm, preprocessing parameters/H0/etc for
      % .data*, .trnRes*.
      %
      % - In some cases where .initData() is called, preprocessing
      % parameters, H0, or channels etc are being mutated. This invalidates
      % the preprocessing procedure on the BG worker and so an asyncReset()
      % often piggybacks initData() calls.
      % - .trnRes* state is set during train/retrain operations. At the
      % start of these operations we do an asyncReset();
      % - trackResInit() is sometimes called when a change in prune 
      % parameters etc is made. In these cases an asyncReset() will follow

      if exist('tfwarn','var')==0
        tfwarn = false;
      end
      
      obj.asyncPredictOn = false;
      if ~isempty(obj.asyncBGClient)
        delete(obj.asyncBGClient);
      else
        tfwarn = false;
      end
      obj.asyncBGClient = [];
      if ~isempty(obj.asyncPredictCPRLTObj)
        delete(obj.asyncPredictCPRLTObj)
      end
      obj.asyncPredictCPRLTObj = [];
      
      if tfwarn
        warningNoTrace('CPRLabelTracker:bg','Cleared background tracker.');
      end
    end
    
    function asyncPrepare(obj)
      % Take current trained tracker and detach; prepare to start worker
      
      obj.asyncReset();
      
      if ~obj.hasTrained
        error('CPRLabelTracker:async','A tracker has not been trained.');
      end
      
      cbkResult = @(sRes)obj.asyncResultReceived(sRes);
      fprintf(1,'Detaching trained tracker...\n');
      objDetached = obj.asyncDetachCopy();
      bgc = BGClient;
      fprintf(1,'Configuring background worker...\n');
      bgc.configure(cbkResult,objDetached,'asyncCompute');
      obj.asyncBGClient = bgc;
      obj.asyncPredictCPRLTObj = objDetached;
    end
    
    function asyncStartBGWorker(obj)
      % Start worker(s) in background thread
      
      bgc = obj.asyncBGClient;
      fprintf(1,'Starting background worker...\n');
      bgc.startWorker();
      obj.asyncPredictOn = true;
      fprintf(1,'Background tracking enabled.\n');
    end
    
    function asyncStopBGWorker(obj)
      % Stop worker(s) on background thread
      
      bgc = obj.asyncBGClient;
      bgc.stopWorker();
      obj.asyncPredictOn = false;
      fprintf(1,'Background tracking disabled.\n');
    end
    
    function asyncTrackCurrFrameBG(obj)
      % Track current frame (send cmd to background)
      
      assert(obj.asyncPredictOn);
      tblP = obj.lObj.labelGetMFTableCurrMovFrmTgt();
      tblP = obj.lObj.preProcCropLabelsToRoiIfNec(tblP);
      sCmd = struct('action','track','data',tblP);
      obj.asyncBGClient.sendCommand(sCmd);
    end
    
    function asyncComputeStats(obj)
      if ~obj.asyncIsPrepared
        error('CPRLabelTracker:async','No background tracking information available.');
      end
      bgc = obj.asyncBGClient;
      tocs = bgc.idTocs;
      if isnan(tocs(end))
        tocs = tocs(1:end-1);
      end
      CPRLabelTracker.asyncComputeStatsStc(tocs);
    end
        
    function sRes = asyncCompute(obj,sCmd)
      % This method intended to run on BGWorker with a "detached" obj
      
      assert(isstruct(obj.lObj),'Expected ''detached'' object.');
      
      switch sCmd.action
        case 'track'
          tblP = sCmd.data;
          assert(istable(tblP));
          [sRes.trkPMDnew,sRes.pTstTRed,sRes.pTstT] = obj.trackCore(tblP);
      end
    end
    
  end
  
  methods (Access=private)
    
    function obj2 = asyncDetachCopy(obj)
      % Create a "detached" copy of obj containing the current trained
      % tracker. This copy contains only that subset of properties
      % necessary for tracking and will be deep-copied onto any/all
      % background workers.
      
      assert(false,'Unsupported. .data, .dataTS, .trnResH0 no longer stored in tracker.');
      
      obj2 = CPRLabelTracker(obj.lObj,'detached',true);
      
      CPFLDS = {'sPrm' 'trnResIPt' 'trnResRC' 'storeFullTracking'};
      for f=CPFLDS,f=f{1}; %#ok<FXSET>
        obj2.(f) = obj.(f);
      end
      obj2.trackResInit();
    end
    
    function asyncResultReceived(obj,sRes)
      % Callback executed when new computation result received from
      % bg worker(s)
      
      if obj.asyncPredictOn % Should always be true, except possibly in 
                            % edge cases when user turns asyncPredict off
        res = sRes.result;
        switch sRes.action
          case 'track'
            obj.updateTrackRes(res.trkPMDnew,res.pTstTRed,res.pTstT); % XXX out of date api
            obj.vizLoadXYPrdCurrMovieTarget();
            obj.newLabelerFrame();
            notify(obj,'newTrackingResults');
          case BGWorker.STATACTION
            computeTimes = res;
            CPRLabelTracker.asyncComputeStatsStc(computeTimes);
          otherwise
            assert(false,'Unrecognized async result received.');
        end
      end
    end    
  end
  methods (Static)
    function asyncComputeStatsStc(computeTimes)
      computeTimes = computeTimes(:);
      nTrk = numel(computeTimes);
      tMu = mean(computeTimes);
      tMax = max(computeTimes);
      tMin = min(computeTimes);
      fprintf(1,'Background compute statistics:\n');
      fprintf(1,' Number of frames tracked in background: %d\n',nTrk);
      fprintf(1,' [min mean max] compute time (s) per frame: %s\n',...
        mat2str([tMin tMu tMax],2));
    end
  end
  
  %% Viz
  methods
    
    %#%MTGT
    function vizInit(obj)
      obj.xyPrdCurrMovie = [];
      obj.xyPrdCurrMovieFull = [];
      obj.xyPrdCurrMovieIsInterp = [];
      deleteValidHandles(obj.hXYPrdRed);
      obj.hXYPrdRed = [];
      deleteValidHandles(obj.hXYPrdRedOther);
      obj.hXYPrdRedOther = [];
      deleteValidHandles(obj.hXYPrdFull);
      obj.hXYPrdFull = [];
      
      % init .xyVizPlotArgs*
      trackPrefs = obj.lObj.projPrefs.Track;
      cprPrefs = obj.lObj.projPrefs.CPRLabelTracker.PredictReplicatesPlot;
      plotPrefs = trackPrefs.PredictPointsPlot;
      plotPrefs.PickableParts = 'none';
      obj.xyVizPlotArgs = struct2paramscell(plotPrefs);
      if isfield(trackPrefs,'PredictInterpolatePointsPlot')
        obj.xyVizPlotArgsInterp = struct2paramscell(trackPrefs.PredictInterpolatePointsPlot);
      else
        obj.xyVizPlotArgsInterp = obj.xyVizPlotArgs;
      end
      obj.xyVizPlotArgsNonTarget = obj.xyVizPlotArgs; % TODO: customize
      if isfield(cprPrefs,'MarkerSize') % AL 201706015: Currently always true
        cprPrefs.SizeData = cprPrefs.MarkerSize^2; % Scatter.SizeData 
        cprPrefs = rmfield(cprPrefs,'MarkerSize');
      end
      obj.xyVizFullPlotArgs = struct2paramscell(cprPrefs);
      
      npts = obj.nPts;
      ptsClrs = obj.lObj.projPrefs.Track.PredictPointsPlotColors;
      ax = obj.ax;
      %arrayfun(@cla,ax);
      arrayfun(@(x)hold(x,'on'),ax);
      ipt2View = obj.lObj.labeledposIPt2View;
      hTmp = gobjects(npts,1);
      hTmpOther = gobjects(npts,1);
      hTmp2 = gobjects(npts,1);
      for iPt = 1:npts
        clr = ptsClrs(iPt,:);
        iVw = ipt2View(iPt);
        hTmp(iPt) = plot(ax(iVw),nan,nan,obj.xyVizPlotArgs{:},'Color',clr,'Tag',sprintf('CPRLabelTracker_XYPrdRed_%d',iPt));
        hTmpOther(iPt) = plot(ax(iVw),nan,nan,obj.xyVizPlotArgs{:},'Color',clr,'Tag',sprintf('CPRLabelTracker_XYPrdRedOther_%d',iPt));
        hTmp2(iPt) = scatter(ax(iVw),nan,nan);
        setIgnoreUnknown(hTmp2(iPt),'MarkerFaceColor',clr,...
          'MarkerEdgeColor',clr,'PickableParts','none',...
          'Tag',sprintf('CPRLabelTracker_XYPrdFull_%d',iPt),...
          obj.xyVizFullPlotArgs{:});
      end
      obj.hXYPrdRed = hTmp;
      obj.hXYPrdRedOther = hTmpOther;
      obj.hXYPrdFull = hTmp2;
      obj.setHideViz(obj.hideViz);
    end
    
    %#%MTGT
    function vizClearReplicates(obj)
      hXY = obj.hXYPrdFull;
      if ~isempty(hXY) % can be empty during initHook
        for iPt = 1:obj.nPts
          set(hXY(iPt),'XData',nan,'YData',nan);
        end
      end
    end
    
    %#%MTGT
    function vizLoadXYPrdCurrMovieTarget(obj)
      % sets .xyPrdCurrMovie* for current Labeler movie and target from 
      % .trkP, .trkPMD

      lObj = obj.lObj;
      
      trkTS = obj.trkPTS;
      if isempty(trkTS) || ~lObj.hasMovie || lObj.currMovie==0
        obj.xyPrdCurrMovie = [];
        obj.xyPrdCurrMovieIsInterp = [];
        obj.xyPrdCurrMovieFull = [];
        return;
      end
      
      nfrms = lObj.nframes;
      ntgts = lObj.nTargets;
      nfids = obj.nPts;
      d = 2;
      mIdx = lObj.currMovIdx;
      iTgt = lObj.currTarget;
      nrep = obj.sPrm.TestInit.Nrep;
      
      [trkpos,~,trkposfull,trkposfullMFT] = obj.getTrackResRaw(mIdx);
      iPtTrk = obj.trkPiPt;
      nptsTrk = numel(iPtTrk);
      szassert(trkpos,[nptsTrk d nfrms ntgts]);
      ntrkfull = height(trkposfullMFT);
      szassert(trkposfull,[nptsTrk d nrep ntrkfull]);
      
      xy = nan(nfids,d,nfrms,ntgts);
      xy(iPtTrk,:,:,:) = trkpos;
      xyfull = nan(nfids,d,nrep,nfrms);
      tfTgt = trkposfullMFT.iTgt==iTgt;
      trkposfullMFT = trkposfullMFT(tfTgt,:);
      trkposfull = trkposfull(:,:,:,tfTgt);
      xyfull(iPtTrk,:,:,trkposfullMFT.frm) = trkposfull;
            
      if obj.trkVizInterpolate && lObj.hasTrx
        warningNoTrace('CPRLabelTracker:interp',...
          'Turning off tracking interpolation; project has trx.');
        obj.trkVizInterpolate = false;
      end
      if obj.trkVizInterpolate
        assert(ntgts==1,'Currently unsupported for multiple targets.');
        [xy,isinterp3] = CPRLabelTracker.interpolateXY(xy);
        isinterp = CPRLabelTracker.collapseIsInterp(isinterp3(iPtTrk,:,:));
      else
        isinterp = false(nfrms,1);
      end

      obj.xyPrdCurrMovie = xy;
      switch obj.storeFullTracking
        case StoreFullTrackingType.NONE
          obj.xyPrdCurrMovieFull = [];
        case {StoreFullTrackingType.FINALITER StoreFullTrackingType.ALLITERS}
          obj.xyPrdCurrMovieFull = xyfull;
        otherwise
          assert(false);
      end
      obj.xyPrdCurrMovieIsInterp = isinterp;
    end

    function setHideViz(obj,tf)
      onoff = onIff(~tf);
      [obj.hXYPrdRed.Visible] = deal(onoff);
      [obj.hXYPrdRedOther.Visible] = deal(onoff);
      obj.hideViz = tf;
    end
            
    function set.showVizReplicates(obj,v)
      assert(isscalar(v));
      v = logical(v);
      if v
        if obj.storeFullTracking==StoreFullTrackingType.NONE && ~obj.isInit %#ok<MCSUP>
          warning('CPRLabelTracker:viz',...
            'Currently not storing tracking replicates. Replicate visualization will be unavailable.');
        end
        [obj.hXYPrdFull.Visible] = deal('on'); %#ok<MCSUP>
      else
        [obj.hXYPrdFull.Visible] = deal('off'); %#ok<MCSUP>
      end
      obj.showVizReplicates = v;      
    end

    function vizInterpolateXYPrdCurrMovie(obj)
      assert(~obj.lObj.hasTrx,'Currently unsupported for multitarget projects.');
      [obj.xyPrdCurrMovie,isinterp3] = CPRLabelTracker.interpolateXY(obj.xyPrdCurrMovie);
      obj.xyPrdCurrMovieIsInterp = CPRLabelTracker.collapseIsInterp(isinterp3);
    end
    
  end

  %%
  methods (Static)
    
    function sPrm0 = readDefaultParams
      tPrm0 = parseConfigYaml(CPRLabelTracker.DEFAULT_PARAMETER_FILE);
      sPrm0 = tPrm0.structize();
      
      % Use nan for npts, nviews; default parameters do not know about any
      % model
      sPrm0 = CPRParam.new2old(sPrm0,nan,nan); 
    end
    
    function sPrm = modernizeParams(sPrm)
      % IMPORTANT philisophical note. This CPR parameter-updating-function
      % currently does not ever alter sPrm in such a way as to invalidate
      % any previous trained trackers or tracking results based on sPrm.
      % Instead, parameters may be renamed, new parameters added, etc; but
      % eg any new parameters added should be added with default values 
      % that effectively would have been previously used.
      %
      % The point is that while most clients of modernizeParams immediately 
      % call .setParamContentsSmart, loadSaveToken() DOES NOT. There, the 
      % contents of the saveToken (trained tracker, results etc) are simply
      % written onto the object. If modernizeParams were to alter the 
      % parameters "materially" then these assignments would be invalid.
      %
      % In the future, if it is necessary to materially alter sPrm, then we
      % need to return a flag indicating whether a material change has
      % occurred so that loadSaveToken can react.

      s0 = CPRLabelTracker.readDefaultParams();
      s0 = rmfield(s0,'PreProc'); % 20180309 PreProc params handled in Labeler
      
      if isfield(sPrm.Reg,'USE_AL_CORRECTION')
        if sPrm.Reg.USE_AL_CORRECTION
          error('CPRLabelTracker:prm',...
            'Project contains obsolete CPR tracking parameter Reg.USE_AL_CORRECTION.');
        end
        assert(~s0.Reg.rotCorrection.use);
        sPrm.Reg = rmfield(sPrm.Reg,'USE_AL_CORRECTION');
      end
      
      % Over time we may remove unused fields from base struture s0; no 
      % need to warn user that we will be dropping these extra fields from 
      % sPrm
      [sPrm,s0used] = structoverlay(s0,sPrm,'dontWarnUnrecog',true); 
      if ~isempty(s0used)
        fprintf('Using default parameters for: %s.\n',...
          String.cellstr2CommaSepList(s0used));
      end
      if isempty(sPrm.Model.nviews)
        % Model.nviews now required. structoverlay would not overlay new
        % default value on top of existing/legacy empty [] value.
        sPrm.Model.nviews = 1;
      end      
      
      % 20170609 iss84. Reg.rotCorrection.use is now the master flag wrt
      % rotations. For now we leave TrainInit.augrotate and
      % TestInit.augrotate present (but empty).
      if ~isempty(sPrm.TrainInit.augrotate) || ~isempty(sPrm.TestInit.augrotate)
        assert(isequal(sPrm.TrainInit.augrotate,sPrm.TestInit.augrotate,...
                       sPrm.Reg.rotCorrection.use),...
          'Inconsistent values of TrainInit.augrotate, TestInit.augrotate, and Reg.rotCorrection.use.');
        sPrm.TrainInit.augrotate = [];
        sPrm.TestInit.augrotate = [];
      end
      
      % 20171003 new jitter fields
      JITTERFLDS = {'doptjitter' 'ptjitterfac' 'doboxjitter'};
      tfTrnInit = isfield(sPrm.TrainInit,JITTERFLDS);
      tfTstInit = isfield(sPrm.TestInit,JITTERFLDS);
      tf = [tfTrnInit(:); tfTstInit(:)];
      assert(all(tf)); % 201803: Given structoverlay above
%       assert(all(tf) || ~any(tf));
%       if ~any(tf) % needs updating
%         assert(~sPrm.TrainInit.augUseFF && ~sPrm.TestInit.augUseFF,...
%             'Cannot update tracking parameters with augUseFF=true.');
%         sPrm.TrainInit.doptjitter = false;
%         sPrm.TestInit.doptjitter = false;
%         sPrm.TrainInit.ptjitterfac = 16; % only placeholder/default, no effect since doptjitter is off
%         sPrm.TestInit.ptjitterfac = 16; % etc
%         sPrm.TrainInit.doboxjitter = true; % on by default prior to 20171003
%         sPrm.TestInit.doboxjitter = true; % on by default prior to 20171003
%       end
      
      % 20171004 rotcorrection from trx
      tf = [isfield(sPrm.TrainInit,'usetrxorientation'); ...
            isfield(sPrm.TestInit,'usetrxorientation')];
      assert(all(tf)); % 201803: Given structoverlay above
%       assert(all(tf) || ~any(tf));
%       if ~any(tf) % needs updating
%         sPrm.TrainInit.usetrxorientation = false;
%         sPrm.TestInit.usetrxorientation = false;
%       end

      % 20180326
      ParameterVisualizationFeature.throwWarningFtrType(sPrm.Ftr.type);
      if strcmp(sPrm.Ftr.type,'1lm')
        warningNoTrace('Feature type ''1lm'' has been renamed to ''single landmark''.');
        sPrm.Ftr.type = 'single landmark';
      end
      
    end
          
    function [xy,isinterp] = interpolateXY(xy)
      % xy (in): [npts d nfrm]
      %
      % xy (out): [npts d nfrm]. Like input, but with nans replaced with
      % values by interpolating along 3rd dim 
      % isinterp: [npts d nfrm] logical.
      
      isinterp = false(size(xy));
      for iPt = 1:size(xy,1)
        for d = 1:size(xy,2)
          z = squeeze(xy(iPt,d,:));
          tf = ~isnan(z);
          if any(tf) % must have at least one nonnan value to interpolate
            iGood = find(tf);
            iNan = find(~tf);
            z(iNan) = interp1(iGood,z(iGood),iNan);
            xy(iPt,d,:) = z;
            isinterp(iPt,d,iNan) = true;
          end
        end
      end
    end
    
    function isinterp1 = collapseIsInterp(isinterp3)
      % isinterp3: [nptsxdxnfrm] logical, see interpolateXY().
      %
      % isinterp1: [nfrm] logical. isinterp1(i) is true if all elements of
      % isinterp3(:,:,i) are true.
      
      [npts,d,nfrm] = size(isinterp3);
      isinterp2 = reshape(isinterp3,[npts*d,nfrm]);
      
      tfall = all(isinterp2,1);
      tfany = any(isinterp2,1);
      tfmixed = tfany & ~tfall;
      nfrmmixed = nnz(tfmixed);
      if nfrmmixed>0
        warning('CPRLabelTracker:isinterp','%d/%d frames have some interpolated and some non-interpolated tracking results. Treating these frames as non-interpolated.',...
          nfrmmixed,nfrm);
      end
      
      isinterp1 = tfall(:);
    end
    
    function tdPPJan(td,varargin)
      td.computeIpp([],[],[],'iTrl',1:td.N,'jan',true,varargin{:});
    end
    
    function tdPPRF(td,varargin)
      td.computeIpp([],[],[],'iTrl',1:td.N,'romain',true,varargin{:});
    end
    
    function tdPPRFfull(td,varargin)
      bppFile = '/groups/branson/home/leea30/rf/2dbot/blurPreProc_21chan.mat';
      bpp = load(bppFile);
      bpp = bpp.bpp(1);
      td.computeIpp([],[],[],'iTrl',1:td.N,'romain',bpp,varargin{:});
    end
    
    function tdPP2dL(td,varargin)
      bppFile = '/groups/branson/home/leea30/rf/rfBlurPreProc.mat';
      bpp = load(bppFile);
      bpp = bpp.bpp(1);
      td.computeIpp([],[],[],'iTrl',1:td.N,'romain',bpp,varargin{:});
    end
    
    function tdPP2dR(td,varargin)
      bppFile = '/groups/branson/home/leea30/rf/rfBlurPreProc.mat';
      bpp = load(bppFile);
      bpp = bpp.bpp(2);
      td.computeIpp([],[],[],'iTrl',1:td.N,'romain',bpp,varargin{:});
    end
    
    function [pTrk,pruneMD] = applyPruning(pTrkFull,pTrkMD,prmPrune)
      % pTrkFull/pTrkMD: See Prune.m
      % prmPrune: prune parameter struct
      %
      % pTrk: [NxD], see Prune.m
      % pruneMD: [N] table of prune-relating metadata
      
      N = size(pTrkFull,1);
      assert(istable(pTrkMD) && height(pTrkMD)==N);
      tblfldscontainsassert(pTrkMD,MFTable.FLDSID);
      
      switch prmPrune.method
        case 'median'
          [pTrk,pruneScore] = Prune.median(pTrkFull);
          pruneMD = table(pruneScore);
        case 'maxdensity'
          [pTrk,pruneScore] = Prune.maxdensity(pTrkFull,...
            'sigma',prmPrune.maxdensity_sigma);
          pruneMD = table(pruneScore);
        case 'maxdensity global'
          [pTrk,pruneScore] = Prune.globalmin(pTrkFull,...
            'sigma',prmPrune.maxdensity_sigma);
          pruneMD = table(pruneScore);
        case 'smoothed trajectory'
          besttrajArgs = {'sigma' prmPrune.maxdensity_sigma ...
            'poslambdafac' prmPrune.poslambdafac};
          [pTrk,pruneMD] = Prune.applybesttraj2segs(pTrkFull,pTrkMD,...
            besttrajArgs);
        otherwise
          assert(false,'Unrecognized pruning method.');
      end
    end
    
  end
  
end

function dpf = lclInitDefaultParameterFile()
if isdeployed
  dpf = fullfile(ctfroot,'params_apt.yaml');
else
  cprroot = fileparts(fileparts(mfilename('fullpath')));
  dpf = fullfile(cprroot,'params_apt.yaml');
end
end
