function [Xbest,idx,totalcost,poslambda] = ...
  ChooseBestTrajectory(X,appearancecost,varargin)
% Select trajectory through CPR-generated replicate clouds 
%
% X: [DxTxK] full CPR tracking results
% appearancecost: [TxK] scalar cost for each shape
%
% Xbest: [DxT] selected replicates representing "best" traj
% idx: [T] replicate indices (indices into 3rd dim of X). Xbest(:,t) is
% equal to X(:,t,idx(t))

[priordistfun,poslambda,dampen,fix] = myparse(varargin,...
  'priordist',@(x) zeros(size(x,1),1),...  % [K] = priordist([KxD]) returns assumed/prior position cost for t=1
  'poslambda',[],... % position costs are multiplied by this scale factor when added to appearance costs
  'dampen',.5,... % velocity damping factor. pos(t) is predicted as pos(t-1)+dampen*(pos(t-1)-pos(t-2)). 1=>full extrapolation, 0=>velocity irrelevant
  'fix',[]);

[D,T,K] = size(X);
szassert(appearancecost,[T K]);

if ~isempty(fix) && numel(fix) ~= T, %#ok<*NOCOL>
  error('fix must be a vector of length T');
end

if ~isempty(fix) && ~all(isnan(fix)),
  
  if ~any(isnan(fix)),
    
    fprintf('All positions fixed, just returning.\n');
    idx = fix; 
    Xbest = nan(D,T);
    for t = 1:T,
      Xbest(:,t) = X(:,t,idx(t));
    end
    totalcost = nan;
    poslambda = nan;
    return;
    
  end
  
  t0 = find(isnan(fix),1);
  t1 = find(isnan(fix),1,'last');
  if t0 > 3 || t1 < T - 2,
  
    args = varargin;
    if t0 > 3,
      t0 = t0 - 2;
      i = find(strcmp(args(1:2:end),'priordist'));
      if ~isempty(i),
        args{2*i} = @(x) zeros(size(x,1),1);
      end
    else
      t0 = 1;
    end
    t1 = min(t1+2,T);
    
    
    idx = fix;
    Xbest = nan(D,T);
    for t = find(~isnan(fix(:)')),
      Xbest(:,t) = X(:,t,idx(t));
    end
    
    fix = fix(t0:t1);
    X = X(:,t0:t1,:);
    appearancecost = appearancecost(t0:t1,:);
    
    i = find(strcmp(args(1:2:end),'fix'));
    if ~isempty(i),
      args(2*i-1:2*i) = [];
    end
    
    [Xbest(:,t0:t1),idx(t0:t1),totalcost,poslambda] = ChooseBestTrajectory(X,appearancecost,args{:},'fix',fix);
  
    return;
  end
end

X = permute(X,[3,1,2]);
szassert(X,[K D T]);

% there are more efficient ways to do this...
if ~isempty(fix),  
  for t = find(~isnan(fix(:)')),    
    appearancecost(t,[1:fix(t)-1,fix(t)+1:K]) = inf;
  end  
end

if isempty(poslambda), 
  
  % Estimate poslambda as ratio of (typical variability in appearance cost)
  % to (typical variability in position cost). The total cost at each
  % timepoint t is poslambda*poscost+appearancecost, and this value is 
  % minimized to find the best trajectory. Note the absolute scales of
  % poscost and appearancecost are irrelevant, the idea here is that
  % poslambda is set so that fluctuations in positioncost and 
  % appearancecost carry comparable weight in the minimization.
  
  Ksample = 5;
  count = (T-2) * Ksample^3;
  errs = nan(1,count);
  off = 0;
  for t = 3:T,
    
    ws = randsample(K,Ksample);
    v = randsample(K,Ksample);
    u = randsample(K,Ksample);
    
    vel = bsxfun(@minus,reshape(X(v,:,t-1),[Ksample,1,D]),reshape(X(u,:,t-2),[1,Ksample,D]));
    predpos = bsxfun(@plus, reshape(X(v,:,t-1),[Ksample,1,D]), dampen*vel);
    
    for w = ws',
      poscost = sum(bsxfun(@minus, reshape(X(w,:,t),[1,1,D]), predpos).^2, 3);
      errs(off+1:off+numel(poscost)) = poscost;
      off = off + numel(poscost);
    end
    
  end
  mad_pos = median( abs( errs(:) - median(errs(:))) );
  mad_app = median( abs( appearancecost(:) - median(appearancecost(:))) );
  poslambda = mad_app/mad_pos;  
end


% initialization

% first frame: position cost is from prior
poscost0 = priordistfun(X(:,:,1));
assert(isvector(poscost0) && numel(poscost0)==K);

% second frame: position cost assumes zero velocity
% poscost1(w,v) corresponds to w at t=2, v at t=1
poscost1 = poslambda * pdist2(X(:,:,2),X(:,:,1),'sqeuclidean');

% [KxK]. costprev(w,v) is the minimum total cost that ends at w at t-1 and
% v at t-2. (Here we will be starting at t=3.)
% This cost is computed as (assumed/prior cost for t=1)+(appearancecost for
% t=1)+(position cost for transitioning from t=1 to t=2)+(appearance cost
% for t=2)
costprev = bsxfun(@plus, poscost0(:)'+appearancecost(1,:), ...
                         bsxfun(@plus, appearancecost(2,:)', poscost1));

% for tracking back and finding optimal states
% prev(v,u,t) gives replicate index (index into 1..K) giving best/chosen 
% replicate w giving minimum w->u->v progression over (t-2)->(t-1)->t
prev = nan(K,K,T);

for t = 3:T,
  
  if mod(t,100) == 0,
    fprintf('Frame %d / %d\n',t,T);
  end
  
  % vel and predpos are K x K x D
  % vel(v,u,:) is the velocity assuming t-2 = u and t-1 = v
  % predpos(v,u,:) is the position assuming t-2 = u and t-1 = v
  vel = bsxfun(@minus,reshape(X(:,:,t-1),[K,1,D]),reshape(X(:,:,t-2),[1,K,D]));
  predpos = bsxfun(@plus, reshape(X(:,:,t-1),[K,1,D]), dampen*vel);
  
  costcurr = nan(K,K);
  
  for w = 1:K,
    
    % poscost is K x K, cost of transitioning from (v,u) to w
    poscost = poslambda * sum(bsxfun(@minus, reshape(X(w,:,t),[1,1,D]), predpos).^2, 3);
    [costcurr(w,:),prev(w,:,t)] = min( appearancecost(t,w) + poscost + costprev, [], 2 );
    
  end

  costprev = costcurr;
  
end

% find the best last state

[totalcost,i] = min(costprev(:));
idx = nan(1,T);
[idx(T),idx(T-1)] = ind2sub([K,K],i);

for t = T-2:-1:1,
  idx(t) = prev(idx(t+2),idx(t+1),t+2);
end

Xbest = nan(D,T);
for t = 1:T,
  Xbest(:,t) = X(idx(t),:,t);
end