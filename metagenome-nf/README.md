# metagenome-nf

宏基因组分析 Nextflow 模块仓库（集群 `Bin_nf/` 的版本化副本）。

当前模块：**metaSPAdes 组装**

```
metagenome-nf/
├── metaspades/              # 模块目录（可直接作为 nextflow 脚本目录运行）
│   ├── main.nf              #   模块入口（含 workflow，单跑用这个）
│   ├── process.nf           #   process 定义（不含 params 块，不能单独作为入口）
│   ├── config               #   模块配置：软件路径 / 镜像 / 默认资源 / publishDir
│   ├── nextflow.config      #   模块配置入口：includeConfig 'config' + profiles
│   ├── sif/                 #   放 metaspades.sif（不入库，自己创建）
│   └── test/                #   项目运行目录（不入库）
├── scripts/
│   └── nfstatus.sh          # 运行状态速查（bash 执行，勿用 sh）
├── examples/
│   └── samples.example.csv  # 样本表模板
└── .gitattributes           # 强制 LF 换行（根治 CRLF 导致的脚本报错）
```

## 集群首次部署

```bash
# 1. 克隆（集群上已有旧目录的话，先备份再改名）
git clone git@github.com:githubholiday/metagenome-nf.git Bin_nf
cd Bin_nf

# 2. 建项目运行目录 + 样本表
mkdir -p metaspades/test && cd metaspades/test
cp ../../examples/samples.example.csv samples.csv
vim samples.csv          # 改成真实样本与绝对路径

# 3. 干跑验证接线（登录节点，秒级，不真跑组装）
nextflow run .. -profile local -stub-run \
  --samples ./samples.csv --outdir ./results
```

干跑通过后投队列：

```bash
nextflow run .. -profile sge --samples ./samples.csv --outdir ./results -resume
```

## 日常更新

**不要在集群上直接改文件**——改完下次 `git pull` 就冲突。流程：

```bash
# Windows 本地改完 → push
git add -A && git commit -m "说明改了什么" && git push

# 集群拉取
cd Bin_nf && git pull
```

## 常用命令

| 目的 | 命令 |
|---|---|
| 查队列真实状态 | `qstat -u tuchengfang` |
| 任务明细（状态/退出码/workdir） | `bash scripts/nfstatus.sh -t metaspades/test` |
| 只看失败任务 + 看日志命令 | `bash scripts/nfstatus.sh -e metaspades/test` |
| 历史 run | `nextflow log`（必须在启动目录里跑） |
| 任务级报告 | `<outdir>/pipeline_info/trace.txt` |
| 打断点续跑 | 原命令加 `-resume` |

## 关键约定（踩过的坑）

1. **`includeConfig` 的相对路径按「包含它的文件所在目录」解析**。本仓库是扁平布局，`metaspades/nextflow.config` 里只写 `includeConfig 'config'`；若出现 `includeConfig 'modules/...'`（流程级写法），会报 `Invalid include source`。
2. **`process.nf` 不能写 `params {}`**。新版 Nextflow 会报 `Params block cannot be defined without an entry workflow`。软件参数默认值一律放 `config`。
3. **`outdir` 需在 `main.nf` 里声明占位**，否则 `--outdir` 触发严格参数检查报 `not declared`。
4. **`executor` 不在模块 `config` 里写死**。写了会覆盖 `-profile`，导致 `-profile local` 失效。
5. **本集群多核任务用 SGE 并行环境 `smp`（PE），不用自定义资源 `p`**：`penv = 'smp'`，Nextflow 自动按 `cpus` 申请核数；`h_vmem` 由 `memory` 自动生成，无需 `cluster.options`。
6. **`samples.csv` 必须有表头** `sample_id,project,r1,r2`；`--samples` 要指向**文件**不是目录。通道为空时 Nextflow 不报错，表现为「几秒 OK 但零任务」。

## 运行模式对照

| 目的 | profile |
|---|---|
| 正式投队列 | `-profile sge` |
| 登录节点冒烟测试 | `-profile local`（勿真跑组装，会抢登录节点资源） |
| 容器环境（需先放 sif） | 叠加 `,singularity`，即 `-profile sge,singularity` |
