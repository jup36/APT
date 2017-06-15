classdef BGClient < handle
  properties
    cbkResult % function handle called when a new result is computed. 
              % Signature:  cbkResult(s) where s has fields .id, .action, .result
    computeObj % Object with method .(computeObjMeth)(s) where s has fields .id, .action, .data
    computeObjMeth % compute method name for computeObj

    qWorker2Me % matlab.pool.DataQueue for receiving data from worker (interrupts)
    qMe2Worker % matlab.pool.PollableDataQueue for sending data to Client (polled)    
    fevalFuture % FevalFuture output from parfeval
    idPool % scalar uint for cmd ids
  end
  properties (Dependent)
    isConfigured
    isRunning 
  end
  methods 
    function v = get.isConfigured(obj)
      v = ~isempty(obj.cbkResult) && ~isempty(obj.computeObj) && ~isempty(obj.computeObjMeth);
    end    
    function v = get.isRunning(obj)
      v = ~isempty(obj.fevalFuture) && strcmp(obj.fevalFuture.State,'running');
    end
  end

  methods 
    function obj = BGClient
      tfPre2017a = verLessThan('matlab','9.2.0');
      if tfPre2017a
        error('BG:ver','Background processing requires Matlab 2017a or later.');
      end
    end
    function delete(obj)
      if ~isempty(obj.qWorker2Me)
        delete(obj.qWorker2Me);
        obj.qWorker2Me = [];
      end
      if ~isempty(obj.qMe2Worker)
        delete(obj.qMe2Worker);
        obj.qMe2Worker = [];
      end
      if ~isempty(obj.fevalFuture)
        obj.fevalFuture.cancel();
        delete(obj.fevalFuture);
        obj.fevalFuture = [];
      end
    end
  end
  
  methods    
    
    function configure(obj,resultCallback,computeObj,computeObjMeth)
      % Configure compute object and results callback
      
      assert(isa(resultCallback,'function_handle'));
      
      obj.cbkResult = resultCallback;
      obj.computeObj = computeObj; % will be deep-copied onto worker
      obj.computeObjMeth = computeObjMeth;
    end
    
    function startWorker(obj)
      % Start BGWorker on new thread
      
      if ~obj.isConfigured
        error('BGClient:config',...
          'Object unconfigured; call configure() before starting worker.');
      end
      
      queue = parallel.pool.DataQueue;
      queue.afterEach(@(dat)obj.afterEach(dat));
      obj.qWorker2Me = queue;
      
      workerObj = BGWorker;
      % computeObj deep-copied onto worker
      obj.fevalFuture = parfeval('start',1,workerObj,queue,obj.computeObj,obj.computeObjMeth); 
      
      obj.idPool = uint32(1);
    end
        
    function sendCommand(obj,sCmd)
      % Send command to worker; startWorker() must have been called
      % 
      % sCmd: struct with fields {'action' 'data'}
            
      if ~obj.isRunning
        error('BGClient:run','Worker is not running.');
      end
      
      assert(isstruct(sCmd) && all(isfield(sCmd,{'action' 'data'})));
      sCmd.id = obj.idPool;
      obj.idPool = obj.idPool + 1;
      
      q = obj.qMe2Worker;
      if isempty(q)
        warningNoTrace('BGClient:queue','Send queue not configured.');
      else
        q.send(sCmd);
        obj.log('Sent command id %d',sCmd.id);
      end
    end
    
    function stopWorker(obj)
      if ~obj.isRunning
        warningNoTrace('BGClient:run','Worker is not running.');
      else
        sCmd = struct('action',BGWorker.STOPACTION,'data',[]);
        obj.sendCommand(sCmd);
      end
    end
    
  end
  
  methods (Access=private)
    
    function log(obj,varargin) %#ok<INUSL>
      str = sprintf(varargin{:});
      fprintf(1,'BGClient (%s): %s\n',datestr(now,'yyyymmddTHHMMSS'),str);
    end
    
    function afterEach(obj,dat)
      if isa(dat,'parallel.pool.PollableDataQueue')
        obj.qMe2Worker = dat;
        obj.log('Received pollableDataQueue from worker.');
      else
        obj.log('Received results id %d',dat.id);
        obj.cbkResult(dat);
      end
    end    
    
  end
  
end