# metaSPAdes Nextflow 模块 · 实战速查手册（v1.0，2026-11-02）

> 把第一天的排障全链路压缩成一份可查手册。集群 `git clone` 后直接看本文件。

## 1. 最终目录布局（扁平，镜像集群 Bin_nf）

```
metagenome-nf/
├── metaspades/
│   ├── main.nf          # 入口（带 workflow + params 块，允许 params）
│   ├── process.nf       # 纯 process 定义（禁止 params 块）
│   ├── config           # 模块配置：软件路径/镜像/资源/publishDir（权威值在这）
│   └── nextflow.config  # 模块自带配置：includeConfig 'config' + profiles + trace
├── scripts/
│   └── nfstatus.sh      # 状态速查脚本（bash 跑，勿用 sh）
├── examples/
│   └── samples.example.csv
├── .gitattributes       # 强制 LF（根治 CRLF 坑）
└── README.md
```

**分层铁律**：样本表/R1/R2/outdir = 项目级；软件/镜像/资源 = 模块级；调度器/步骤顺序 = 流程级（pipeline.yaml）。

**输出路径规范（所有模块统一）**：`outdir/<模块名>/<sample_id>/` —— `publishDir` 根 = `${params.outdir}/<模块名>`（**不含 sample 层**），样本层由产物文件名/目录名（含 `${sample_id}`）提供；去掉了 project 维度与 `_xxx` 子目录嵌套。例如 metaSPAdes 最终落点：`outdir/metaspades/A10/`（内含 final.contig.fa、scaffolds.fasta、gfa、log 等）。

## 2. 运行命令（在 test/ 这类项目目录下）

```bash
# 单模块正式跑（投 SGE，宿主机裸跑）
nextflow run ../ -profile sge --samples ./samples.csv --outdir ./results

# 单模块 + Singularity 容器
nextflow run ../ -profile sge,singularity --samples ./samples.csv --outdir ./results

# 登录节点干跑验证接线（秒级，不真跑）
nextflow run ../ -profile local -stub-run --samples ./samples.csv --outdir ./results

# 断点续跑（只重跑失败任务）
nextflow run ../ -profile sge --samples ./samples.csv --outdir ./results -resume
```

⚠ `--samples` 必须指向**文件**（samples.csv），不能是目录；`samples.csv` 第一行必须是表头 `sample_id,project,r1,r2`。

## 3. 状态查询

```bash
qstat -u tuchengfang                      # SGE 队列真实状态（qw 排队/r 运行/Eqw 出错）
qacct -j <job_id>                         # 任务结束后的退出码与峰值内存

bash ../scripts/nfstatus.sh -p <Bin_nf根>  # 总览所有项目最近一次 run
bash ../scripts/nfstatus.sh -t <项目目录>  # 每个任务：状态/exit/workdir
bash ../scripts/nfstatus.sh -e <项目目录>  # 只列失败任务 + 直接给出看日志的命令
```

`nextflow log` 只能在**启动目录**跑（读 `./.nextflow/history`）。每个 run 自动落盘 `<outdir>/pipeline_info/trace.txt`（含 workdir 列）+ `report.html`。

## 4. 排障速查表

| 现象 / 报错 | 根因 | 修法 |
|---|---|---|
| `Unexpected input: 'path'`（config 里） | `publishDir path: ...` 是 process 脚本语法，config 里不合法 | config 用 `publishDir = [ path: { "..." }, mode: 'copy' ]`（赋值+闭包） |
| `Params block cannot be defined without an entry workflow` | process.nf 是纯 process 文件，禁止 params 块 | 软件默认值放模块 `config`，process.nf 不写 params |
| `Parameter 'outdir' was specified but not declared` | 单跑模块时配置链无 outdir 声明 | main.nf 的 params 块加 `outdir = 'results'` 占位 |
| `Unknown configuration profile: 'sge'` | 模块 nextflow.config 没定义 profiles | 模块 nextflow.config 补 profiles（sge/k8s/local+singularity/docker） |
| 加了 `-profile local` 仍投 SGE | 模块 config 写死 `executor='sge'`（per-process 优先于 profile） | executor 不在模块 config 声明，交给 profile / pipeline.yaml |
| `job denied: use parallel environments...` | 集群不认 Nextflow 默认多核请求 | 标准 PE 用 `penv='<名>'`；自定义资源用 `cluster.options='-l p=N,vf=...'`（与 cpus 一致） |
| `Invalid include source` | 模块目录被流程级 nextflow.config 覆盖 | 模块 nextflow.config 只留 `includeConfig 'config'`，出现 modules/ 或 pipeline.generated 即被覆盖 |
| `$'\r': 未找到命令` / `set -o pipefail 无效` | 文件是 CRLF；用 `sh` 跑 bash 脚本 | `sed -i 's/\r$//'` 转 LF；脚本用 `bash` 或 `./` 跑，勿用 `sh` |
| run 秒级 OK 且 qstat 无任务 | samples 通道为空（fromPath 不报错） | 查 `--samples` 路径是否存在、是否指向文件、表头是否齐全 |
| `spades-hammer ... OS return value: 12` | ENOMEM，内存不够 | `memory`/`cluster.options` 的 `vf=`/`cpus`/`p=` **四处同步调大** |
| 字符损坏（`>=`→`≥`、`=` 消失） | 复制粘贴/聊天工具中转代码 | 一律用 git/scp，禁止文本中转 |

## 5. git 同步方案（根治传输损坏）

```bash
# 本机改完 push
cd metagenome-nf && git add -A && git commit -m "..." && git push

# 集群首次
git clone git@github.com:githubholiday/metagenome-nf.git
# 之后每次
cd metagenome-nf && git pull
```

`.gitattributes` 已强制 `* text=auto eol=lf`，从根上消除 CRLF。待办：GitHub 建空仓库 `metagenome-nf`（不勾 README/gitignore）后即可 `git push -u origin main`。

## 6. 已知未决

- 远端 GitHub 仓库尚未创建 → push 未执行（SSH 已验证可用）。
- 内存 250G/32 核为占位上限，A10 实测若仍 ENOMEM 需继续上调。
- 多模块阶段再上 `pipeline/`（两层布局 + yaml 驱动串联），届时 singularity 开关需改 profile 化。
