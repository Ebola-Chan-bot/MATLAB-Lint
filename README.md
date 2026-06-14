当前市面上缺少一款纯 MATLAB 编写的高级代码风格审查器，本库填补此空缺。

当前内置规则（共 19 条，规则 ID 即函数名）：
| 规则 ID                        | 说明                             |
|-------------------------------|----------------------------------|
| `mlint_noAccumulatorPlaceholder`    | 禁止累积器类占位空初始化（豁免 `table()` 与 `isempty` 决策变量） |
| `mlint_noZeroRepeatCount`           | 禁止使用包含 0 重复数的 `repmat/repelem`，要求重构逻辑并移除该需求 |
| `mlint_noRedundantNestedIf`         | 禁止仅包裹单个 if 且无其它语句/else 的外层 if，建议合并为单层 if |
| `mlint_mergePatternCallChain`       | 同函数同首参数的连续 `startsWith/contains` `||` 链必须合并为一次调用并用 `|` 连接 pattern |
| `mlint_noDescendingColonRange`      | 禁止起点大于终点的双参数冒号范围（如 `5:3`），要求重构逻辑并移除对此模式的需求 |
| `mlint_noStructArray`               | 禁止 struct 数组，建议改用 table    |
| `mlint_singleUseVariable`           | 一次性中间变量 / 未使用变量         |
| `mlint_multiStatementLine`          | 禁止分号压行                      |
| `mlint_singleTileLayout`            | 单 tile 的 tiledlayout 冗余       |
| `mlint_noBuiltin`                   | 禁止 `builtin(...)` 调用          |
| `mlint_usePatternInsteadOfRegexp`   | 建议用 pattern 替代 regexp        |
| `mlint_mergeSkipIfChain`            | 连续同动作 skip-if 链应合并        |
| `mlint_noNonarithCast`              | 禁止无算术场景的整数类型转换         |
| `mlint_noRedundantSortUnique`       | 禁止 `sort(unique(...))` 冗余写法  |
| `mlint_mergeAlwaysNestedLocalFn`    | 总是嵌套调用的局部函数建议合并       |
| `mlint_noContainersMap`             | 建议用 dictionary 替代 containers.Map |
| `mlint_noSingleLineFunction`        | 禁止只有一行有效代码的函数，建议内联 |
| `mlint_noCatTableAppend`            | 仅允许 `MATLAB.DataTypes.InsertiveTable` 的 `end+1` 插入；普通 table 的 `end+1` 与 cat/拼接均禁止 |
| `mlint_mergeSameRowAssignments`     | 同一行多列分散赋值应合并为单行 |

找不到任何配置时，默认启用全部规则。

# 快速开始

在 MATLAB 中将项目根目录加入路径后运行：

```matlab
issues = MatlabLint.lint(".");
```

或检查单文件：

```matlab
issues = MatlabLint.lint("project_lint.m");
```

返回值 `issues` 为 `table`，字段如下：
- `file`
- `line`
- `rule`
- `message`

### 查看规则状态

```matlab
s = MatlabLint.listRules();
```

返回 `table`，字段：
- `rule` — 规则 ID
- `description` — 中文描述
- `enabled` — 是否启用
- `source` — 最终生效来源（`默认`、`用户级`、`当前目录`、`目标目录`、`参数`、`自定义`）

### 写入规则开关到配置文件

```matlab
% 写入到用户级配置（默认开启）
configPath = MatlabLint.addRule("myRule");

% 写入到指定目录的 .matlablint.json
configPath = MatlabLint.addRule("myRule", ".");

% 写入到指定 json 文件并关闭该规则
configPath = MatlabLint.addRule("mlint_noBuiltin", "C:/work/.matlablint.json", false);

% 仅传启用开关（按类型推断）
configPath = MatlabLint.addRule("mlint_noBuiltin", false);

% 可选参数顺序无关（string 是路径，logical 是开关）
configPath = MatlabLint.addRule("mlint_noBuiltin", true, "C:/work/.matlablint.json");

% 写入命名空间函数（保存在 Id）
configPath = MatlabLint.addRule("pkg.validators.checkName", ".");

% 写入文件路径规则（保存在 Id）
configPath = MatlabLint.addRule("C:/myProject/rules/checkNaming.m", ".");
```

- `ruleId` 作为规则标识值写入 JSON 条目值
- `configPathOrDir` 可传目录或 `.json` 文件路径；省略时写入用户级配置
- `enabled` 省略时为 `true`
- 可选参数可无序传入，并按类型推断：`string/char` 为 `configPathOrDir`，`logical` 为 `enabled`
- 返回值 `configPath` 为实际写入的配置文件路径

# 目录结构

```text
+MatlabLint/
	lint.m                       % 主入口
	listRules.m                  % 查询规则启用状态与生效层级
	stripStringLiterals.m        % 共享工具：剔除字符串字面量
	private/                     % 内部实现，不对外暴露
		...(所有内部函数)
```

框架按以下顺序覆盖（后者覆盖前者）：
1. 用户级配置
2. 当前目录配置：`.matlablint.json`
3. 目标代码文件所在目录配置：`.matlablint.json`
4. 调用时传入的可选位置参数 `cfg`（最高优先级）

用户级配置存放位置（建议）：
- Windows: `%APPDATA%/MATLAB-Lint/.matlablint.json`
- macOS/Linux: `~/.config/matlab-lint/.matlablint.json`

示例 `.matlablint.json`（配置键统一使用英文，与 MATLAB `cfg` 结构体保持一致）：

```json
{
  "OutputToConsole": true,
  "Exclude": [
    "**/resources/**",
    "**/.git/**"
  ],
  "Rules": [
    { "Id": "mlint_noAccumulatorPlaceholder", "Enabled": true },
    { "Id": "mlint_noZeroRepeatCount", "Enabled": true },
    { "Id": "mlint_noRedundantNestedIf", "Enabled": true },
    { "Id": "mlint_mergePatternCallChain", "Enabled": true },
    { "Id": "mlint_noDescendingColonRange", "Enabled": true },
    { "Id": "mlint_noStructArray", "Enabled": true },
    { "Id": "mlint_singleUseVariable", "Enabled": true },
    { "Id": "mlint_multiStatementLine", "Enabled": true },
    { "Id": "mlint_singleTileLayout", "Enabled": true },
    { "Id": "mlint_noBuiltin", "Enabled": true },
    { "Id": "mlint_usePatternInsteadOfRegexp", "Enabled": true },
    { "Id": "mlint_mergeSkipIfChain", "Enabled": true },
    { "Id": "mlint_noNonarithCast", "Enabled": true },
    { "Id": "mlint_noRedundantSortUnique", "Enabled": true },
    { "Id": "mlint_mergeAlwaysNestedLocalFn", "Enabled": true },
    { "Id": "mlint_noContainersMap", "Enabled": true },
    { "Id": "mlint_noSingleLineFunction", "Enabled": true },
    { "Id": "mlint_noCatTableAppend", "Enabled": true },
    { "Id": "mlint_mergeSameRowAssignments", "Enabled": true }
  ]
}
```

调用参数示例：

```matlab
cfg = struct();
cfg.OutputToConsole = true;
cfg.Rules = [struct("Id", "mlint_noBuiltin", "Enabled", false)];
issues = MatlabLint.lint(".", cfg);
```

# 新增自定义规则

编写一个签名为 `(filePath)` 的函数（可放在任意路径），然后在配置中写入函数名或 .m 文件路径即可启用。文件内容由规则函数自行读取。

## 函数签名

```matlab
function issues = myRule(filePath)
```

## 输入参数

| 参数       | 类型          | 说明 |
|-----------|--------------|------|
| `filePath` | `string` 标量 | 当前被检查 .m 文件的完整路径 |

规则函数内自行读取文件内容：
```matlab
txt = fileread(filePath);
lines = splitlines(string(txt));
```

## 返回值

函数必须返回一个 `table`，包含以下 4 列（列名固定）：

| 列名      | 类型      | 说明 |
|----------|----------|------|
| `file`   | `string` | 出问题的文件路径（通常直接传回 `filePath`） |
| `line`   | `double` | 行号（从 1 开始） |
| `rule`   | `string` | 规则标识（建议用函数名字符串，如 `"myRule"`） |
| `message`| `string` | 问题描述，自由文本 |

- 如果该文件未发现任何问题，返回 **空 table**（0 行 × 4 列）即可
- 如有多个问题，纵向拼接（`[issues; newIssue]`），每个 newIssue 为一行 table
- 可用 `table(string(filePath), double(i), "myRule", "message text", ... 'VariableNames', {"file","line","rule","message"})` 构造单行

## 完整示例

```matlab
function issues = myRule(filePath)
% 示例规则：禁止使用 'eval'
% 无参数调用时返回中文描述文本，供 listRules 显示

if nargin == 0
    issues = "禁止使用 eval";
    return;
end

issues = table( ...
    string.empty(0,1), double.empty(0,1), string.empty(0,1), string.empty(0,1), ...
    'VariableNames', {"file", "line", "rule", "message"});

txt = fileread(filePath);
lines = splitlines(string(txt));

for i = 1:numel(lines)
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;  % 跳过空行与注释
    end
    if contains(s, "eval(")
        newIssue = table(string(filePath), double(i), "myRule", ...
            sprintf('Avoid eval: %s', s), ...
            'VariableNames', {"file", "line", "rule", "message"});
        issues = [issues; newIssue]; %#ok<AGROW>
    end
end
end
```

> **约定**：自定义规则函数在 `nargin == 0`（无参调用）时应返回一条中文描述字符串。`listRules` 会利用此机制为所有已知规则（含自定义）显示描述列。

## 配置启用

```json
{
  "Rules": [
    { "Id": "myRule", "Enabled": true },
    { "Id": "C:/myProject/rules/checkNaming.m", "Enabled": true }
  ]
}
```

- **函数名**：确保该函数在 MATLAB 路径中
- **文件路径**：写 .m 文件的完整路径，框架自动将其所在目录加入路径并解析函数句柄