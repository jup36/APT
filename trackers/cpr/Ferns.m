classdef Ferns
  
  methods (Static)
    
    function [inds,mu,ysFern,count] = test
      N = 1000;
      M = 5;
      D = 7;
      fids = 1:M;
      reg = .01;
      thrr = [-.2 .2];
      thrs = rand(1,M)*(thrr(2)-thrr(1))+thrr(1);
      
      X = 2*rand(N,M)-1;
      Y = 2*rand(N,D)-1;
      dY = bsxfun(@minus,Y,mean(Y));
      
      tic; [inds2,mu2,ysFern2,count2] = fernsInds2(X,uint32(fids),thrs,Y); toc
      tic; [inds3,ysFern3,count3,ysFernCnt3] = Ferns.fernsInds3(X,fids,thrs,dY); toc
      assert(isequal(inds2,inds3));
      assert(isequal(ysFern2,ysFern3));
      assert(isequal(count2,count3));
      
      inds = inds2;
      mu = mu2;
      ysFern = ysFern2;
      count = count2;
    end

    function [inds,dyFernSum,count,dyFernCnt] = fernsInds3(X,fids,thrs,dY)
      % Fern binner that allows nans in Y.
      %
      % X: [NxF] features
      % fids: [S] feature indices (indices into cols of X) to use
      % thrs: [S] thresholds for fids
      % dY: [NxD] de-meaned shapes (column means should be 0)
      %
      % inds: [N] fern bin (1..2^S) for datapts
      % dyFernSum: [2^SxD] sum of dY for each fern bin, treating NaNs 
      %   as missing
      % count: [2^S] number of datapoints (rows of X) in each fern bin
      % dyFernCnt: [2^SxD] sum of counts for each fernbin/coord, treating
      %   NaNs as missing
      %
      % Formulas:
      %
      % <nanmean-fern shape for bin iBin> = ysFern(iBin,:)./ysFernCnt(iBin,:)
      %
      % ysFernCnt(iBin,j) <= count(iBin) for all j.
      
      [N,F] = size(X); %#ok<ASGLU>
      [Ntmp,D] = size(dY);
      assert(N==Ntmp);
      assert(isvector(fids));
      S = numel(fids);
      assert(isvector(thrs) && numel(thrs)==S);

      assert(nnz(isnan(X))==0);      
      S2 = 2^S;
      
      inds = zeros(N,1);
      for s=1:S
        f = fids(s);
        for i=1:N
          inds(i) = inds(i)*2;
          if X(i,f)<thrs(s)
            inds(i) = inds(i)+1;
          end
        end
      end
      inds = inds+1;
      
      count = zeros(S2,1);
      dyFernSum = zeros(S2,D);
      dyFernCnt = zeros(S2,D);
      for i = 1:N
        s = inds(i);
        count(s) = count(s)+1;
        
        tfgood = ~isnan(dY(i,:));
        dyFernSum(s,tfgood) = dyFernSum(s,tfgood) + dY(i,tfgood);
        dyFernCnt(s,tfgood) = dyFernCnt(s,tfgood) + 1;
      end      
    end
    
  end
  
end