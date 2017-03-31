% Session holds the state of the Camera Calibration App
%
%   This class holds the entire state of the camera calibration UI.
%   It is used to save and load the camera calibration session. It is also
%   used to pass data amongst other classes.

% Copyright 2012-2013 The MathWorks, Inc.

classdef Session < handle

    properties
        CameraModel;              % holds all of the calibration options
        OptimizationOptions = [];      % initial values for intrinsics and radial distortion
        CameraParameters = [];    % actual calibration results
        EstimationErrors = [];
        ShouldExportErrors = false;
        
        BoardSet = [];            % holds all checkerboard information
        
        HasEnoughBoards = false;  % true if enough images were loaded and processed
        CanExport = false;        % true when cameraParameters can be exported
        IsChanged = false;        % true when session may need saving
        
        ExtrinsicsView = 'CameraCentric';
        
        % ErrorsView is no longer used, since we only use the BarGraph view
        % in the app. However, we have to keep this property around for
        % compatibility with older versions.
        ErrorsView = 'BarGraph';
        
        Filename = []; % filename for the session
        
        ExportVariableName = 'cameraParams'; % default export variable name     
        ExportErrorsVariableName = 'estimationErrors';
    end
    
    properties(Access=private, Hidden)
        Version = ver('vision');
    end
        
    properties(Dependent)
        FileName; % Had to add this for backward compatibility
        
        % The following properties are NOT mutually exclusive.
        % An empty session (with empty BoardSet and CameraParameters) can 
        % be either stereo or single camera. 
        IsValidStereoCameraSession;
        IsValidSingleCameraSession;
    end
    
    methods
        
        %------------------------------------------------------------------
        function fileName = get.FileName(this)
            fileName = this.Filename;
        end
        
        %------------------------------------------------------------------
        function set.FileName(this, fileName)
            this.Filename = fileName;
        end
        
        %------------------------------------------------------------------
        function tf = get.IsValidStereoCameraSession(this)
            tf = (isempty(this.CameraParameters) || ...
                  isa(this.CameraParameters, 'stereoParameters')) && ...
                 (isempty(this.BoardSet) || ...
                  size(this.BoardSet.FullPathNames, 1) == 2);
        end
        
        %------------------------------------------------------------------
        function tf = get.IsValidSingleCameraSession(this)
            tf = (isempty(this.CameraParameters) || ...
                  isa(this.CameraParameters, 'cameraParameters')) && ...
                 (isempty(this.BoardSet) || ...
                  size(this.BoardSet.FullPathNames, 1) == 1);
        end
            
        %------------------------------------------------------------------
        % return true if the tool went though the calibration
        %------------------------------------------------------------------
        function ret = isCalibrated(this)
            ret = ~isempty(this.CameraParameters);
        end

        function ret = hasAnyBoards(this)
            ret = ~isempty(this.BoardSet) && ...
                    this.BoardSet.NumBoards ~= 0;
        end        
        
        %------------------------------------------------------------------
        function reset(this)
            
            this.ExtrinsicsView = 'CameraCentric';
            this.FileName = [];
            this.CanExport = false;
            this.HasEnoughBoards = false;
            this.CameraParameters = [];
            this.IsChanged = false;
            this.CameraModel = [];
            this.OptimizationOptions = [];
            
            if ~isempty(this.BoardSet)
                this.BoardSet.reset();
            end
        end
        
        %------------------------------------------------------------------
        % Wipes only the calibration portion of the session
        %------------------------------------------------------------------
        function resetCalibration(this)
            this.CanExport = false;
            this.CameraParameters = [];
        end
        
        %------------------------------------------------------------------
        function checkImagePaths(this, pathname, filename)
            if ~isempty(this.BoardSet)
                this.BoardSet.checkImagePaths(pathname, filename);
            end
        end
        
        %------------------------------------------------------------------

    end
    
    methods (Static)
      function res = hlpOrthoSingleCalib(camidx,camSess)
        camParams = camSess.CameraParameters;
        nCalIm = camParams.NumPatterns;
        worldPts = camParams.WorldPoints;
        bs = camSess.BoardSet;
        imPtsUV = bs.BoardPoints;
        
        p0 = OrthoCam.p0fromRsTs(...
          permute(camParams.RotationMatrices,[2 1 3]),...
          camParams.TranslationVectors);
        
        fprintf(1,'Calibrating camera %d... ',camidx);
        pause(1);
        pOpt = OrthoCam.calibrate1cam(nCalIm,worldPts,imPtsUV,p0);
        fprintf(1,'done.\n');
        pause(1);

        res = struct();
        res.p0 = p0;
        res.pOpt = pOpt;
        %res.oFcn = oFcn;
        res.nPat = nCalIm;
        res.worldPts = worldPts;
        res.imPtsUV = imPtsUV;
        res.boardSetFPNs = bs.FullPathNames;
        res.ts = now();        
      end
      function dRP = hlpAssessOrthoSingleCalib(camSess,pOpt)
        
        camParams = camSess.CameraParameters;
        nCalIm = camParams.NumPatterns;
        worldPoints = camParams.WorldPoints;
        nPts = size(worldPoints,1);
        szassert(worldPoints,[nPts 2]);
        worldPtsXYZ = [worldPoints zeros(nPts,1)]';
        
        bs = camSess.BoardSet;
        imPtsUV = bs.BoardPoints;
        szassert(imPtsUV,[nPts 2 nCalIm]);        
        calibImPts = permute(imPtsUV,[2 1 3]);
      
        oFcn = @(p)OrthoCam.oFcn(p,nCalIm,worldPtsXYZ,calibImPts);
        dRP = oFcn(pOpt);
        dRP = reshape(dRP,[nPts nCalIm]);
      end
      function [calRes,calResFile] = hlpLoadSingleOrthoCamCalRes(camidx)
        str = sprintf('Select saved single-Orthocam calibration for Camera%d.',camidx);
        [fname,pth] = uigetfile('*.mat',str);
        if isequal(fname,0)
          calRes = [];
          calResFile = '';
        else
          calResFile = fullfile(pth,fname);
          calRes = load(calResFile,'-mat');
        end
      end
      function calResFile = hlpSaveSingleOrthoCamCalRes(calres,camidx) %#ok<INUSL>
        str = sprintf('Save single-Orthocam calibration for Camera%d.',camidx);
        [fname,pth] = uiputfile('*.mat',str);
        if isequal(fname,0)
          calResFile = '';
        else
          calResFile = fullfile(pth,fname);
          save(calResFile,'-struct','calres');
        end
      end
    end
    methods
      function [sess,sessMatfile] = hlpLoadAndCheckSingleCamSession(this,camidx)
        str = sprintf('Select Camera%d Session/MAT-file saved from MATLAB Camera Calibrator App',camidx);
        [fname,pth] = uigetfile('*.mat',str);
        if isequal(fname,0)
          sess = [];
          sessMatfile = '';
        else
          sessMatfile = fullfile(pth,fname);
          sess = load(sessMatfile,'-mat');
          sess = sess.calibrationSession;
          tf = ismember(this.BoardSet.FullPathNames(camidx,:)',sess.BoardSet.FullPathNames');
          if ~all(tf)
            error('Session:cal','One or more %s calibration images are not present in single-camera session: %s\n',...
              ['cam' num2str(camidx)],sessMatfile);
          end
        end
      end
      function [r2vecs,t2vecs] = hlpSelSingleCamExtrinsics(this,iCam,res)
        pOpt = res.pOpt;
        nCalIm = res.nPat;
        fpnsMono = res.boardSetFPNs(:);        
        szassert(fpnsMono,[nCalIm 1]);
        fpnsStro = this.BoardSet.FullPathNames(iCam,:)';
        [tf,loc] = ismember(fpnsStro,fpnsMono);
        assert(all(tf));
        fprintf(1,'Selecting %d (rvec,tvec) extrinsic pairs out of %d from cam%d extrinsics:\n',...
          numel(fpnsStro),nCalIm,iCam);

        [~,~,~,~,~,~,r2vecs,t2vecs] = OrthoCam.unpack1cam(pOpt,nCalIm);
        r2vecs = r2vecs(:,loc);
        t2vecs = t2vecs(:,loc);        
      end
      
      function imagesUsed = calibrate(this)        
        info = struct();
        [info.cam1Sess,info.cam1SessMatfile] = this.hlpLoadAndCheckSingleCamSession(1);
        [info.cam2Sess,info.cam2SessMatfile] = this.hlpLoadAndCheckSingleCamSession(2);
                
        LOAD = 'Load existing orthocam calibrations';
        CALIB = 'Perform orthocam calibrations now';
        CANCEL = 'Cancel';
        resp = questdlg('Do you have existing single-camera OrthoCam calibrations for these two cameras?',...
          'Load existing OrthoCam calibrations (single-cam)',...
          LOAD,CALIB,CANCEL,CALIB);
        if isempty(resp)
          resp = CANCEL;
        end
        info.monoCalOrigin = 'none'; % {'none','loaded','run'}
        switch resp
          case LOAD
            [info.cam1calres,info.cam1calresfile] = this.hlpLoadSingleOrthoCamCalRes(1);
            [info.cam2calres,info.cam2calresfile] = this.hlpLoadSingleOrthoCamCalRes(2);
            if isempty(info.cam1calres) || isempty(info.cam2calres)
              resp2 = questdlg('Do you want to perform OrthoCam calibrations now?',...
                'Perform OrthoCam calibrations','Yes','No','Yes');
              if isempty(resp2)
                resp2 = 'No';
              end
              switch resp2
                case 'Yes'
                  % none
                case 'No'
                  error('Session:cal','Calibration canceled.');
              end
              info.monoCalOrigin = 'run';
            else
              info.monoCalOrigin = 'loaded';
            end
          case CALIB
            info.monoCalOrigin = 'run';
          case CANCEL
            error('Session:cal','Calibration canceled.');
        end
        switch info.monoCalOrigin
          case 'run'
            info.cam1calres = this.hlpOrthoSingleCalib(1,info.cam1Sess);
            info.cam2calres = this.hlpOrthoSingleCalib(2,info.cam2Sess);
            info.cam1calresfile = '';
            info.cam2calresfile = '';
            fprintf(1,'Done with single-cam calibrations. Results:\n');
          case 'loaded'
            fprintf(1,'Loaded single-cam calibrations. Reproj error on current images:\n');
        end
        
        % summarize intrinsics; and RP err
        dRP1 = this.hlpAssessOrthoSingleCalib(info.cam1Sess,info.cam1calres.pOpt);
        dRP2 = this.hlpAssessOrthoSingleCalib(info.cam2Sess,info.cam2calres.pOpt);
        mu1 = mean(dRP1(:));
        mu2 = mean(dRP2(:));        
        hFig = figure;
        ax = subplot(1,2,1);
        OrthoCam.vizRPerr(ax,dRP1);
        cprms1 = info.cam1Sess.CameraParameters;
        tstr = sprintf('cam1 mono-calib. %dpats, %dpts. mean RPerr=%.3f px',...
            cprms1.NumPatterns,size(cprms1.WorldPoints,1),mu1); 
        title(tstr,'fontweight','bold');
        ylabel('count','fontweight','bold');
        ax = subplot(1,2,2);
        OrthoCam.vizRPerr(ax,dRP2);
        cprms2 = info.cam2Sess.CameraParameters;
        tstr = sprintf('cam2 mono-calib. %dpats, %dpts. mean RPerr=%.3f px',...
            cprms2.NumPatterns,size(cprms2.WorldPoints,1),mu2);
        title(tstr,'fontweight','bold');
                
        nCalIm1 = cprms1.NumPatterns;
        nCalIm2 = cprms2.NumPatterns;
        pOpt1 = info.cam1calres.pOpt;
        pOpt2 = info.cam2calres.pOpt;
        tblIntsMono = [ OrthoCam.summarizeIntrinsics(pOpt1,nCalIm1); ...
                        OrthoCam.summarizeIntrinsics(pOpt2,nCalIm2) ];
        tblIntsMono.Properties.RowNames = {'monocal-cam1' 'monocal-cam2'};        
        disp(tblIntsMono);
        input('hit enter to continue');
        
        % offer to save monocal res if we just ran
        % XXX default filename: based on info.cam1SessMatfile etc
        switch info.monoCalOrigin
          case 'run'
            resp = questdlg('Save single-camera OrthoCam calibrations?',...
              'Save calibrations',...
              'Yes, save','No','Cancel','Yes, save');
            if isempty(resp)
              resp = 'Cancel';
            end
            switch resp
              case 'Yes, save'
                info.cam1calresfile = this.hlpSaveSingleOrthoCamCalRes(info.cam1calres,1);
                info.cam2calresfile = this.hlpSaveSingleOrthoCamCalRes(info.cam2calres,2);
                % files may be '' if user cancels
              case 'No'
                % none
              case 'Cancel'
                error('Session:cal','Calibration canceled.');
            end
        end
        
        % pick out extrinsics
        [r2vecs1,t2vecs1] = this.hlpSelSingleCamExtrinsics(1,info.cam1calres);
        [r2vecs2,t2vecs2] = this.hlpSelSingleCamExtrinsics(2,info.cam2calres);

        [r2veccam1,t2veccam1,r2veccam2,t2veccam2,rvecsPat,tvecsPat] = ...
          OrthoCam.estimateStroExtrinsics(r2vecs1',t2vecs1',r2vecs2',t2vecs2');
        
        tblInts1 = tblIntsMono(1,:);
        tblInts2 = tblIntsMono(2,:);
        p0 = OrthoCam.packParamsStro( ...
          tblInts1.mx,tblInts1.my,tblInts1.u0,tblInts1.v0,tblInts1.k1,tblInts1.k2,...
          tblInts2.mx,tblInts2.my,tblInts2.u0,tblInts2.v0,tblInts2.k1,tblInts2.k2,...
          r2veccam1,t2veccam1,r2veccam2,t2veccam2,rvecsPat,tvecsPat);
        
        bset = this.BoardSet;
        nPat = bset.NumBoards;
        % SELECT WORLD COORDSYS/"first" pattern
%         fpnsStro1 = bset.FullPathNames(1,:)';
%         [sel,ok] = listdlg('PromptString','Select pattern to serve as world 
        
        pOpt = p0;
        dsums = nan(0,2);
        while 1
          [pOpt,oFcn,dsums(end+1,1),dsums(end+1,2)] = OrthoCam.calibrateStro(nPat,bset.WorldPoints,...
            bset.BoardPoints(:,:,:,1),bset.BoardPoints(:,:,:,2),pOpt);
          STOP = 'Stop optimization, looks good';
          RESTART = 'Restart optimization';
          CANCEL = 'Cancel';
          resp = questdlg('Restart optimization?','Optimization waypoint',...
            STOP,RESTART,CANCEL,STOP);
          if isempty(resp)
            resp = CANCEL;
          end
          switch resp
            case STOP
              break;
            case RESTART
              % none; while loop will proceed
            case CANCEL
              error('Session:cal','Calibration canceled.');
          end
        end
              
        % RP err
        dRP = oFcn(pOpt);
        npts = size(this.BoardSet.BoardPoints,1);
        dRP = reshape(dRP,[npts nPat 2]);
        hFig = figure;
        dRP1 = dRP(:,:,1);
        dRP2 = dRP(:,:,2);
        mu1 = mean(dRP1(:));
        mu2 = mean(dRP2(:));
        ax = subplot(1,2,1);
        OrthoCam.vizRPerr(ax,dRP1);
        title(sprintf('Stereo calib, cam1. %dpats, %dpts. mean RPerr=%.3f px',nPat,npts,mu1),...
          'fontweight','bold');
        ylabel('count','fontweight','bold');
        ax = subplot(1,2,2);
        OrthoCam.vizRPerr(ax,dRP2);
        title(sprintf('Stereo calib, cam2. meanRP err=%.3f px',mu2),'fontweight','bold');
      
        % Summarize
        tblIntsStro = OrthoCam.summarizeIntrinsicsStro(pOpt,nPat);
        tblInts = [tblIntsMono;tblIntsStro];
        tblInts.Properties.RowNames = ...
          {'cam1/monocal' 'cam2/monocal' 'cam1/strocal' 'cam2/strocal'};
        tblInts = tblInts([1 3 2 4],:);
        disp(tblInts);

        patPtsXYZ = this.BoardSet.WorldPoints';
        patPtsXYZ = [patPtsXYZ; zeros(1,npts)];
        [~,~,~,~,~,~,~,~,~,~,~,~,r2vec1,t2vec1,r2vec2,t2vec2,rvecs,tvecs] = ...
          OrthoCam.unpackParamsStro(pOpt,nPat);
        hFig = OrthoCam.viewExtrinsics(patPtsXYZ,rvecs,tvecs,...
          r2vec1,t2vec1,r2vec2,t2vec2);

        res = struct();
        res.p0 = p0;
        res.pOpt = pOpt;        
        res.boardSet = bset;
        res.ts = now();
        
        
        
        
        % viz extrinsics

            if isempty(this.OptimizationOptions) || ...
                    isempty(this.OptimizationOptions.InitialDistortion)
                numRadial = this.CameraModel.NumDistortionCoefficients;                
            else
                numRadial = numel(this.OptimizationOptions.InitialDistortion);
            end
            
            if ~isempty(this.OptimizationOptions)
                initIntrinsics = this.OptimizationOptions.InitialIntrinsics;
                initDistortion = this.OptimizationOptions.InitialDistortion;
            else
                initIntrinsics = [];
                initDistortion = [];
            end
            
            [cameraParams, imagesUsed, estimationErrors] = ...
                estimateCameraParameters(this.BoardSet.BoardPoints, ...
                this.BoardSet.WorldPoints,...
                'EstimateSkew', this.CameraModel.ComputeSkew, ...
                'EstimateTangentialDistortion', ...
                this.CameraModel.ComputeTangentialDistortion, ...
                'NumRadialDistortionCoefficients', numRadial, ...
                'WorldUnits', this.BoardSet.Units, ...
                'ShowProgressBar', true, ...
                'InitialIntrinsicMatrix', initIntrinsics, ...
                'InitialRadialDistortion', initDistortion);
            
            this.CanExport = true;
            this.IsChanged = true;
            this.CameraParameters = cameraParams;
            this.EstimationErrors = estimationErrors;
        end
        
        %------------------------------------------------------------------
        function codeString = generateCode(this)
            if isa(this.CameraParameters, 'stereoParameters')
                codeString = generateCodeStereo(this);
            else
                codeString = generateCodeSingle(this);
            end
        end
    end
    
    methods(Access=private)
        %------------------------------------------------------------------
        function codeString = generateCodeSingle(this)
            cameraModel = this.CameraModel;
            codeGenerator = vision.internal.calibration.tool.MCodeGenerator;            

            % Write a header
            codeGenerator.addHeader('cameraCalibrator');

            % Detect checkerboards
            codeGenerator.addComment('Define images to process'); 
            codeGenerator.addLine(sprintf('imageFileNames = %s;',...
                cell2str(this.BoardSet.FullPathNames)));

            codeGenerator.addComment('Detect checkerboards in images');
            codeGenerator.addLine('[imagePoints, boardSize, imagesUsed] = detectCheckerboardPoints(imageFileNames);');
            codeGenerator.addLine('imageFileNames = imageFileNames(imagesUsed);');

            % Set up data for the calibration
            codeGenerator.addComment('Generate world coordinates of the corners of the squares');
            codeGenerator.addLine(sprintf('squareSize = %d;  %% in units of ''%s''',...
                this.BoardSet.SquareSize,...
                this.BoardSet.Units));
            codeGenerator.addLine('worldPoints = generateCheckerboardPoints(boardSize, squareSize);');

            % Calibrate
            if isempty(this.OptimizationOptions)
                initIntrinsics = [];
                initDistortion = [];
            else
                initIntrinsics = this.OptimizationOptions.InitialIntrinsics;
                initDistortion = this.OptimizationOptions.InitialDistortion;
            end
            
            codeGenerator.addComment('Calibrate the camera');
            codeGenerator.addLine(sprintf(['[cameraParams, imagesUsed, estimationErrors] = estimateCameraParameters(imagePoints, worldPoints, ...\n',...
                '''EstimateSkew'', %s, ''EstimateTangentialDistortion'', %s, ...\n', ...
                '''NumRadialDistortionCoefficients'', %d, ''WorldUnits'', ''%s'', ...\n', ...
                '''InitialIntrinsicMatrix'', %s, ''InitialRadialDistortion'', %s);'], ...
                mat2str(cameraModel.ComputeSkew), ...
                mat2str(cameraModel.ComputeTangentialDistortion),...
                cameraModel.NumDistortionCoefficients, this.BoardSet.Units, ...
                mat2str(initIntrinsics), mat2str(initDistortion)));

            % Add visualizations
            
            % Reprojection errors
            codeGenerator.addComment('View reprojection errors');            
            codeGenerator.addLine('h1=figure; showReprojectionErrors(cameraParams);');
            
            % Extrinsics
            codeGenerator.addComment('Visualize pattern locations');
            codeGenerator.addLine(sprintf('h2=figure; showExtrinsics(cameraParams, ''%s'');', ...
                this.ExtrinsicsView));

            % Estimation errors
            codeGenerator.addComment('Display parameter estimation errors');
            codeGenerator.addLine('displayErrors(estimationErrors, cameraParams);');

            % Suggest possible next steps
            codeGenerator.addComment('For example, you can use the calibration data to remove effects of lens distortion.');
            codeGenerator.addLine('originalImage = imread(imageFileNames{1});');
            codeGenerator.addLine('undistortedImage = undistortImage(originalImage, cameraParams);');
            
            codeGenerator.addComment('See additional examples of how to use the calibration data.  At the prompt type:');
            codeGenerator.addLine('% showdemo(''MeasuringPlanarObjectsExample'')');
            codeGenerator.addLine('% showdemo(''StructureFromMotionExample'')');
            
            % Terminate the file with carriage return
            codeGenerator.addReturn();
            
            codeString = codeGenerator.CodeString;            
        end
        
        %------------------------------------------------------------------
        function codeString = generateCodeStereo(this)
            cameraModel = this.CameraModel;
            codeGenerator = vision.internal.calibration.tool.MCodeGenerator;    
            
            % Write a header
            codeGenerator.addHeader('stereoCalibrator');

            % Detect checkerboards
            codeGenerator.addComment('Define images to process'); 
            codeGenerator.addLine(sprintf('imageFileNames1 = %s;',...
                cell2str(this.BoardSet.FullPathNames(1, :))));
            codeGenerator.addLine(sprintf('imageFileNames2 = %s;',...
                cell2str(this.BoardSet.FullPathNames(2, :))));

            codeGenerator.addComment('Detect checkerboards in images');
            codeGenerator.addLine('[imagePoints, boardSize, imagesUsed] = detectCheckerboardPoints(imageFileNames1, imageFileNames2);');

            % Set up data for the calibration
            codeGenerator.addComment('Generate world coordinates of the checkerboard keypoints');
            codeGenerator.addLine(sprintf('squareSize = %d;  %% in units of ''%s''',...
                this.BoardSet.SquareSize,...
                this.BoardSet.Units));
            codeGenerator.addLine('worldPoints = generateCheckerboardPoints(boardSize, squareSize);');

            % Calibrate
            if isempty(this.OptimizationOptions)
                initIntrinsics = [];
                initDistortion = [];
            else
                initIntrinsics = this.OptimizationOptions.InitialIntrinsics;
                initDistortion = this.OptimizationOptions.InitialDistortion;
            end
            
            codeGenerator.addComment('Calibrate the camera');
            codeGenerator.addLine(sprintf(['[stereoParams, pairsUsed, estimationErrors] = estimateCameraParameters(imagePoints, worldPoints, ...\n',...
                '''EstimateSkew'', %s, ''EstimateTangentialDistortion'', %s, ...\n', ...
                '''NumRadialDistortionCoefficients'', %d, ''WorldUnits'', ''%s'', ...\n', ...
                '''InitialIntrinsicMatrix'', %s, ''InitialRadialDistortion'', %s);'], ...
                mat2str(cameraModel.ComputeSkew), ...
                mat2str(cameraModel.ComputeTangentialDistortion),...
                cameraModel.NumDistortionCoefficients, this.BoardSet.Units, ...
                mat2str(initIntrinsics), mat2str(initDistortion)));

            % Add visualizations
            
            % Reprojection errors
            codeGenerator.addComment('View reprojection errors');            
            codeGenerator.addLine('h1=figure; showReprojectionErrors(stereoParams);');
            
            % Extrinsics
            codeGenerator.addComment('Visualize pattern locations');
            codeGenerator.addLine(sprintf('h2=figure; showExtrinsics(stereoParams, ''%s'');', ...
                this.ExtrinsicsView));
            
            % Estimation errors
            codeGenerator.addComment('Display parameter estimation errors');
            codeGenerator.addLine('displayErrors(estimationErrors, stereoParams);');
            
            % Suggest possible next steps
            codeGenerator.addComment('You can use the calibration data to rectify stereo images.');
            codeGenerator.addLine('I1 = imread(imageFileNames1{1});');
            codeGenerator.addLine('I2 = imread(imageFileNames2{1});');
            codeGenerator.addLine('[J1, J2] = rectifyStereoImages(I1, I2, stereoParams);');
            
            codeGenerator.addComment('See additional examples of how to use the calibration data.  At the prompt type:');
            codeGenerator.addLine('% showdemo(''StereoCalibrationAndSceneReconstructionExample'')');
            codeGenerator.addLine('% showdemo(''DepthEstimationFromStereoVideoExample'')');
            
            % Terminate the file with carriage return
            codeGenerator.addReturn();
            
            codeString = codeGenerator.CodeString;
        end
    end
    
    %----------------------------------------------------------------------
    % saveobj and loadobj are implemented to ensure compatibility across
    % releases even if architecture of Session class changes
    methods (Hidden)
       
        function that = saveobj(this)            
            that.version         = this.Version;
            that.cameraModel     = this.CameraModel;
            that.optimizationOptions = this.OptimizationOptions;
            that.cameraParams    = this.CameraParameters;
            that.estimationErrors = this.EstimationErrors;
            that.shouldExportErrors = this.ShouldExportErrors;
            that.boardSet        = this.BoardSet;
            that.hasEnoughBoards = this.HasEnoughBoards;
            that.canExport       = this.CanExport;
            that.isChanged       = this.IsChanged;
            that.extrinsicsView  = this.ExtrinsicsView;
            that.errorsView      = this.ErrorsView;
            that.filename        = this.FileName;
            that.exportVarName   = this.ExportVariableName;
        end
        
    end
    
    %----------------------------------------------------------------------
    methods (Static, Hidden)
       
        function this = loadobj(that)
            if isa(that, 'vision.internal.calibration.tool.Session')
                this = that;
                this.OptimizationOptions.InitialIntrinsics = [];
                this.OptimizationOptions.InitialDistortion = [];
            else
                this = vision.internal.calibration.tool.Session;
                this.CameraModel        = that.cameraModel;
                this.CameraParameters   = that.cameraParams;
                this.EstimationErrors   = that.estimationErrors;
                this.ShouldExportErrors = that.shouldExportErrors;
                this.BoardSet           = that.boardSet;
                this.HasEnoughBoards    = that.hasEnoughBoards;
                this.CanExport          = that.canExport;
                this.IsChanged          = that.isChanged;
                this.ExtrinsicsView     = that.extrinsicsView;
                this.FileName           = that.filename;
                this.ExportVariableName = that.exportVarName;
                
                if isfield(that, 'optimizationOptions')
                    this.OptimizationOptions = that.optimizationOptions;
                else
                    this.OptimizationOptions.InitialIntrinsics = [];
                    this.OptimizationOptions.InitialDistortion = [];
                end
            end
        end
        
    end
end

%--------------------------------------------------------------
% This function handles conversion of cell array of strings
% to a string representing the entire cell array
%--------------------------------------------------------------
function str = cell2str(cellArray)
str = '{'; % opening bracket

% constants that are easier to read once assigned into
% variables
quote = '''';
nextLine = sprintf(',...\n');

for i=1:numel(cellArray)
    str = [str, quote, cellArray{i}, quote, nextLine]; %#ok<AGROW>
end

str = [str, '}']; % closing bracket
end