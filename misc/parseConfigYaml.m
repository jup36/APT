function t = parseConfigYaml(filename)
% t = parseConfigYaml(filename)
% Parse a configuration yaml.

s = ReadYaml(filename);
t = lclParse(s);

function tagg = lclParse(s)
fns = fieldnames(s);
tagg = [];
for f=fns(:)',f=f{1}; %#ok<FXSET>
  val = s.(f);
  isLeaf = iscell(val) && ischar(val{1});
  if isLeaf
    pgp = PropertiesGUIProp(f,val{1:end-1},val{end-1:end});
    t = TreeNode(pgp);
  else
    pgp = PropertiesGUIProp(f,val{1}{1:end-1},val{1}{end-1:end});
    t = TreeNode(pgp);
    % 20170426: cell2mat, cellfun still don't handle obj arrays    
    children = cellfun(@lclParse,val(2:end),'uni',0);
    t.Children = cat(1,children{:}); 
  end
  tagg = [tagg;t]; %#ok<AGROW>
end
