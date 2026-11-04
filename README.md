# Binning_nf

宏基因组分析 Nextflow 流程仓库（集群 `Bin_nf/` 的版本化副本）。

两步链：**metaSPAdes 组装 → metaSPAdes 回帖（align）**。

```
Binning_nf/
├── pipeline/                     # 流程本体（流程级，可复用，与项目无关）
│   ├── main.nf                   #   工作流：MetaSpades → MetaSpades_Align（手写串写，含双路 join）
│   ├── nextflow.config           #   流程级配置：include 各模块 / singularity / sge·local·k8s profile
│   ├── pipeline.yaml             #   步骤链声明（数据驱动：assemble → align）
│   ├── pipeline.generated.config #   由 yaml2config.py 从 yaml 自动生成的资源配置
│   ├── modules/                  #   模块库
│   │   ├── metaspades/           #     组装模块（main.nf/process.nf/config/nextflow.config）
│   │   ├── metaspades_align/     #     回帖模块（contigs 来自上一步通道，不进 sample.csv）
│   │   └── _template/            #     新模块模板
│   ├── scripts/                  #   pipeline2main.py / yaml2config.py / nfstatus.sh / nfyaml.py
│   ├── examples/                 #   samples.example.csv（样本表模板，三列）
│   └── sif/                      #   容器镜像目录（空，不入库）
├── project/                      # 项目级运行配置（当前 238 项目）
│   ├── nextflow.config           #   本项目参数：outdir / workDir / 样本表路径 / Para_* 元信息
│   ├── samples.csv               #   样本表（三列：sample_id,r1,r2）
│   └── comparison.csv            #   比较组表
├── prepare/                      # 旧 make/bash 流程「准备阶段」参数存档（中转参考，不参与运行）
│   ├── params.conf               #   原 config.ini [Para] 节参数
│   ├── samples.csv
│   └── comparison.csv
├── run_sge.sh                    # 集群运行入口（check / submit / monitor / module）
├── .gitattributes                # 强制 LF 换行（根治 CRLF 导致的脚本报错）
└── .gitignore
```

## 集群首次部署

```bash
# 1. 克隆（集群上已有旧目录的话，先备份再改名）
git clone git@github.com:githubholiday/Binning_nf.git
cd Binning_nf

# 2. 建项目运行目录 + 样本表
cd project
cp ../pipeline/examples/samples.example.csv samples.csv
vim samples.csv          # 改成真实样本与绝对路径（三列：sample_id,r1,r2）
```

## 运行（在 project/ 下执行，流程本体在 ../pipeline）

```bash
# 登录节点干跑验证接线（秒级，不真跑组装）
nextflow run ../pipeline -profile local -stub-run \
  --samples ./samples.csv --outdir ./results

# 正式投队列（断点续跑）
nextflow run ../pipeline -profile sge --samples ./samples.csv --outdir ./results -resume
```

或直接用入口脚本：

```bash
bash ../run_sge.sh check     # 预检：环境、路径、配置
bash ../run_sge.sh submit    # 把 nextflow 主进程投递到 SGE 队列（推荐）
bash ../run_sge.sh monitor   # 查看已投递任务与产出
```

## 分层铁律（改文件前先读）

| 层 | 放什么 | 文件 |
|---|---|---|
| 流程级 | 步骤顺序、模块资源、调度器、软件/镜像 | `pipeline/nextflow.config`、`pipeline.yaml`、`pipeline/modules/*/config` |
| 项目级 | 样本表、outdir/workDir、项目元信息（Para_*） | `project/nextflow.config`、`project/samples.csv` |

- **改流程接线**（步骤、join）→ 只动手写 `pipeline/main.nf`，**勿用 `pipeline2main.py` 覆盖它**（align 的双路 join 生成器表达不了）。
- **改资源配置** → 改 `pipeline/pipeline.yaml`，再 `python pipeline/scripts/yaml2config.py pipeline/pipeline.yaml` 重生成 `pipeline.generated.config`。
- **换项目** → 只改 `project/` 三件套，不动 `pipeline/`。

## 常用命令

| 目的 | 命令 |
|---|---|
| 查队列真实状态 | `qstat -u tuchengfang` |
| 任务明细（状态/退出码/workdir） | `bash pipeline/scripts/nfstatus.sh -t project` |
| 只看失败任务 + 看日志命令 | `bash pipeline/scripts/nfstatus.sh -e project` |
| 历史 run | `nextflow log`（必须在启动目录里跑） |
| 任务级报告 | `<outdir>/pipeline_info/trace.txt` |
| 打断点续跑 | 原命令加 `-resume` |

## 关键约定（踩过的坑）

1. **`includeConfig` 相对路径按「包含它的文件所在目录」解析**。`metaspades/nextflow.config` 只写 `includeConfig 'config'`；流程级 `nextflow.config` 才写 `includeConfig 'modules/...'`。混用会报 `Invalid include source`。
2. **`process.nf` 不写 `params {}`**（新版 Nextflow 报 `Params block cannot be defined without an entry workflow`）。软件默认值一律放模块 `config`。
3. **`outdir` 需在 `main.nf` 或 `project/nextflow.config` 声明占位**，否则 `--outdir` 触发严格检查报 `not declared`。
4. **`executor` 不在模块 `config` 写死**，交给 `-profile`，否则 `-profile local` 失效。
5. **本集群多核任务用 SGE 并行环境 `smp`（PE）**：`penv = 'smp'`，Nextflow 按 `cpus` 申请核数；`h_vmem` 由 `memory` 自动生成。
6. **`samples.csv` 必须有表头** `sample_id,r1,r2`；`--samples` 指向**文件**不是目录。通道为空时 Nextflow 不报错，表现为「几秒 OK 但零任务」。
7. **`metaspades_align` 的 contigs 来自上一步 `MetaSpades` 的通道**（逐样本 `final.contig.fa`），**不进 sample.csv**；模块 standalone 的 `contig_fa` 参数只服务于单独跑该模块。

## 运行模式对照

| 目的 | profile |
|---|---|
| 正式投队列 | `-profile sge` |
| 登录节点冒烟测试 | `-profile local`（勿真跑组装，抢登录节点资源） |
| 容器环境（需先放 sif） | 叠加 `,singularity`，即 `-profile sge,singularity` |

## 日常更新

**不要在集群上直接改文件**——改完下次 `git pull` 就冲突。流程：

```bash
# 本地（Windows）改完 → push
git add -A && git commit -m "说明改了什么" && git push

# 集群拉取
cd Binning_nf && git pull
```

> 排障速查见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
