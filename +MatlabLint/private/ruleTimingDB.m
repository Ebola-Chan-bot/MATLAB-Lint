function db = ruleTimingDB(action, varargin)
%RULETIMINGDB 管理规则历史累计耗时数据库。
% db = ruleTimingDB('load')   — 加载数据库（按累计耗时降序排序）
% ruleTimingDB('update', ruleName, elapsed) — 更新某规则的累计耗时

persistent dbPath;
persistent rulesDb;

if isempty(dbPath)
    dbPath = fullfile(getenv('PUBLIC'), 'MATLAB-Lint', '.rule_timing.json');
end

if strcmp(action, 'load')
    if ~isempty(rulesDb)
        db = rulesDb;
        return;
    end
    rulesDb = iLoad();
    % 按累计耗时降序排序
    if ~isempty(rulesDb) && isfield(rulesDb, 'Rules')
        [~, order] = sort([rulesDb.Rules.totalSec], 'descend');
        rulesDb.Rules = rulesDb.Rules(order);
    end
    db = rulesDb;
elseif strcmp(action, 'update')
    ruleName = varargin{1};
    elapsed = varargin{2};
    if isempty(rulesDb)
        rulesDb = iLoad();
    end
    rulesDb = iMerge(rulesDb, ruleName, elapsed);
    iSave(rulesDb);
elseif strcmp(action, 'clear')
    rulesDb = [];
    dbPath = [];
end
end

% -------------------------------------------------------------------------
function db = iLoad()
raw = fullfile(fullfile(getenv('PUBLIC'), 'MATLAB-Lint'), '.rule_timing.json');

if ~isfile(raw)
    db = struct('Rules', struct('id', {}, 'totalSec', {}, 'runs', {}));
    return;
end

try
    raw = fileread(raw);
    if isempty(raw)
        db = struct('Rules', struct('id', {}, 'totalSec', {}, 'runs', {}));
        return;
    end
    db = jsondecode(raw);
catch
    db = struct('Rules', struct('id', {}, 'totalSec', {}, 'runs', {}));
end
end

% -------------------------------------------------------------------------
function db = iMerge(db, ruleId, elapsed)
if ~isfield(db, 'Rules') || isempty(db.Rules)
    db.Rules = struct('id', char(ruleId), 'totalSec', elapsed, 'runs', 1);
    return;
end

for i = 1:numel(db.Rules)
    if strcmp(db.Rules(i).id, ruleId)
        db.Rules(i).totalSec = db.Rules(i).totalSec + elapsed;
        db.Rules(i).runs = db.Rules(i).runs + 1;
        return;
    end
end

% 新规则：用结构体字面量直接赋值
db.Rules = struct('id', {db.Rules.id, char(ruleId)}, ...
    'totalSec', {db.Rules.totalSec, elapsed}, ...
    'runs', {db.Rules.runs, 1});
end

% -------------------------------------------------------------------------
function iSave(db)
fid = fullfile(getenv('PUBLIC'), 'MATLAB-Lint');
if ~isfolder(fid)
    mkdir(fid);
end

try
    raw = jsonencode(db, PrettyPrint=true);
catch
    raw = jsonencode(db);
end

fid = fopen(fullfile(fid, '.rule_timing.json'), 'w');
if fid < 0
    return;
end
fwrite(fid, raw, 'char');
fclose(fid);
end