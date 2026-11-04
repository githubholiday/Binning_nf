# Binning_nf 实战速查手册（v2.0，2026-11-04）

> metagenome-nf 已并入 Binning_nf（删除重复的 metaspades 模块与脚本，独有文档提升到仓库根）。集群 `git clone` 后直接看本文件。

## 1. 最终目录布局（镜像集群 Binning_nf）

```
Binning_nf/
├── pipeline/                     # 流程本体（流程级）
│   ├── main.nf                   #   工作流：MetaSpades → MetaSpades_Align（手写串写）
│   ├── nextflow.config           #   流程级配置：include 各模块 + profiles + singularity
│   ├── pipeline.yaml             #   步骤链声明（assemble → align）
│   ├── pipeline.generated.config #   yaml2config.py 生成的资源配置
│   ├── modules/
│   │   ├── metaspades/           #   组装模块（main.nf / process.nf / config / nextflow.config）
│   │   ├── metaspades_align/     #   回帖模块
│   │   └── _template/
│   ├── scripts/                  #   nfstatus.sh / pipeline2main.py / yaml2config.py / nfyaml.py
│   └── examples/samples.example.csv
├── project/                      # 项目级：project.config（用 -c 指定）/ samples.csv / comparison.csv
├── prepare/                      # 旧流程参数存档（参考用，不参与运行）
└── run_sge.sh                    # 集群运行入口
```

**分层铁律**：样本表/R1/R2/outdir = 项目级（`project/`，config 用 `-c` 指定）；软件/镜像/资源 = 模块级（`pipeline/modules/*/config`）；调度器/步骤顺序 = 流程级（`pipeline/nextflow.config` + `pipeline.yaml`）。

**输出路径规范（所有模块统一）**：`outdir/<模块名>/<sample_id>/` —— `publishDir` 根 = `${params.outdir}/<模块名>`（**不含 sample 层**），样本层由产物文件名/目录名（含 `${sample_id}`）提供。例如 metaSPAdes 最终落点：`outdir/metaspades/A10/`（内含 final.contig.fa、scaffolds.fasta、gfa、log 等）。

## 2. 运行命令（在 project/ 下）

```bash
# 两步流程正式跑（投 SGE，宿主机裸跑）
nextflow run ../pipeline -profile sge --samples ./samples.csv --outdir ./results

# 两步流程 + Singularity 容器
nextflow run ../pipeline -profile sge,singularity --samples ./samples.csv --outdir ./results

# 登录节点干跑验证接线（秒级，不真跑）
nextflow run ../pipeline -profile local -stub-run --samples ./samples.csv --outdir ./results

# 断点续跑（只重跑失败任务）
nextflow run ../pipeline -profile sge --samples ./samples.csv --outdir ./results -resume

# 只跑单模块（调试）：流程级配置用 -c 叠加
nextflow run ../pipeline/modules/metaspades/main.nf -c ../pipeline/nextflow.config -profile sge
```

⚠ `--samples` 必须指向**文件**（samples.csv），不能是目录；`samples.csv` 第一行必须是表头 `sample_id,r1,r2`（**三列，已去掉 project 列**）。

## 3. 状态查询

```bash
qstat -u tuchengfang                      # SGE 队列真实状态（qw 排队/r 运行/Eqw 出错）
qacct -j <job_id>                         # 任务结束后的退出码与峰值内存

bash pipeline/scripts/nfstatus.sh -p <Binning_nf根>  # 总览所有项目最近一次 run
bash pipeline/scripts/nfstatus.sh -t project         # 每个任务：状态/exit/workdir
bash pipeline/scripts/nfstatus.sh -e project         # 只列失败任务 + 直接给出看日志的命令
```

`nextflow log` 只能在**启动目录**跑（读 `./.nextflow/history`）。每个 run 自动落盘 `<outdir>/pipeline_info/trace.txt`（含 workdir 列）+ `report.html`。

## 4. 排障速查表

| 现象 / 报错 | 根因 | 修法 |
|---|---|---|
| `Unexpected input: 'path'`（config 里） | `publishDir path: ...` 是 process 语法，config 不合法 | config 用 `publishDir = [ path: { "..." }, mode: 'copy' ]`（赋值+闭包） |
| `Params block cannot be defined without an entry workflow` | process.nf 是纯 process 文件，禁止 params 块 | 软件默认值放模块 `config`，process.nf 不写 params |
| `Parameter 'outdir' was specified but not declared` | 配置链无 outdir 声明 | 已在 `pipeline/main.nf` params 块声明占位；确认集群代码已 `git pull` 到含此修复的版本 |
| `Unknown configuration profile: 'sge'` | 没定义 profiles | 流程级 `nextflow.config` 补 profiles（sge/k8s/local+singularity/docker） |
| 加了 `-profile local` 仍投 SGE | 模块 config 写死 `executor='sge'`（per-process 优先于 profile） | executor 不写死，交给 profile / pipeline.yaml |
| `job denied: use parallel environments...` | 集群不认 Nextflow 默认多核请求 | 标准 PE 用 `penv='<名>'`；自定义资源用 `cluster.options='-l p=N,vf=...'` |
| `Invalid include source` | 模块目录被流程级 nextflow.config 覆盖 | 模块 nextflow.config 只留 `includeConfig 'config'`，不出现 `modules/` 或 `pipeline.generated` |
| `$'\r': 未找到命令` / `set -o pipefail 无效` | 文件是 CRLF；用 `sh` 跑 bash 脚本 | `sed -i 's/\r$//'` 转 LF；脚本用 `bash` 或 `./` 跑，勿用 `sh` |
| run 秒级 OK 且 qstat 无任务 | samples 通道为空（fromPath 不报错） | 查 `--samples` 路径是否存在、是否指向文件、表头是否齐全 |
| `spades-hammer ... OS return value: 12` | ENOMEM，内存不够 | `memory`/`cluster.options` 的 `vf=`/`cpus`/`p=` **四处同步调大** |
| `No such property: contig` / `not defined` | main.nf 接线错（如错用 `.into` 变量、引用不存在的 emit） | align 的 contigs 来自上一步通道：从组装目录 `map` 派生 final.contig.fa 再 `join(samples, by:[0])`；勿用 `pipeline2main.py` 覆盖 main.nf |
| 字符损坏（`>=`→`≥`、字段错位） | 复制粘贴/聊天工具中转代码 | 一律用 git/scp，禁止文本中转 |

## 5. git 同步方案（根治传输损坏）

```bash
# 本机改完 push
git add -A && git commit -m "..." && git push

# 集群首次
git clone git@github.com:githubholiday/Binning_nf.git
# 之后每次
cd Binning_nf && git pull
```

`.gitattributes` 已强制 `* text=auto eol=lf`，从根上消除 CRLF。

## 6. 已知未决

- 内存 250G/32 核为占位上限，A10 实测若仍 ENOMEM 需继续上调（memory / cpus / cluster.options 同步）。
- metaspades 当前走**非容器**（shanzhong 的 conda 环境二进制）；若切回 Singularity，需把 `metaspades.sif` 放进 `pipeline/sif/`（该镜像不入库，需自行传输）。
- `project/comparison.csv` 目前仅表头，比较组待填；`prepare/` 为旧流程参数存档，仅作溯源参考。
| `couldn't allocate memory for bam_mem` | samtools sort 启动即预分配 线程数×-m 内存（**单进程**）；登录节点 ulimit -v 太小，或 SGE 下 task.memory 被均分到各 slot（单进程额度=memory/cpus），预分配超过单进程额度即失败 | 已修：process.nf 中 sort 线程压到 2、-m 按「单 slot 额度×80%」自动推导（20GB/8slot→-m 1G→预分配 2G）；如需覆盖用 `--bam_sort_mem`（自行评估 ulimit） |
