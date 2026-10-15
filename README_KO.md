# Conda Environment Tunnel Deploy

Windows PC가 여는 역방향 SSH 터널을 통해, 인터넷이 되는 relay 서버의 Conda 환경 하나를 인터넷이 차단된 컨테이너로 배포합니다.

```text
Windows PC: open-tunnel.ps1
        │ reverse SSH tunnel
        ▼
Relay 서버: deploy-conda-env.sh ENV_NAME
        │ pack → transfer → remote install → validate
        ▼
컨테이너: ~/anaconda/envs/ENV_NAME
```

사용자가 실행하는 명령은 두 개입니다.

```powershell
# Windows
.\open-tunnel.ps1
```

```bash
# Relay
./deploy-conda-env.sh testconn
```

## 1. 파일과 역할

| 파일 | 실행 위치 | 역할 |
|---|---|---|
| `open-tunnel.ps1` | Windows PC | relay에서 컨테이너로 들어가는 역방향 터널 개방 |
| `deploy-conda-env.sh` | relay 서버 | 환경 패킹, 전송, 원격 설치, 검증 |
| `bridge.conf.example` | 공통 | 배포 가능한 설정 예시 |
| `bridge.conf` | Windows와 relay | 실제 접속 정보. Git에 올라가지 않음 |

컨테이너에는 이 저장소를 복사할 필요가 없습니다. relay의 배포 스크립트가 터널을 통해 원격 명령을 실행합니다.

## 2. 최초 설정

### Windows PC

```powershell
git clone https://github.com/mj-chung1113/offline-wheel-bridge.git
Set-Location offline-wheel-bridge
Copy-Item bridge.conf.example bridge.conf
notepad bridge.conf
```

### Relay 서버

```bash
git clone https://github.com/mj-chung1113/offline-wheel-bridge.git
cd offline-wheel-bridge
chmod +x deploy-conda-env.sh
```

Windows에서 작성한 실제 설정 파일을 relay로 복사합니다.

```powershell
scp .\bridge.conf "[relay 사용자명]@[relay 서버 주소]:~/offline-wheel-bridge/bridge.conf"
```

`bridge.conf`에는 비밀번호나 개인키를 넣지 않습니다. 이 파일은 `.gitignore`에 포함되어 있습니다.

## 3. 설정 파일

다음은 설정 구조입니다. **[필수 수정]**만 먼저 설정하고, **[선택]**은 필요할 때만 바꿉니다.

```bash
# [필수 수정] Windows가 접속할 두 서버
RELAY_USER="[relay 서버 사용자명]"
RELAY_HOST="[relay 서버 IP 또는 도메인]"
CLUSTER_HOST="[클러스터 IP 또는 도메인]"
CLUSTER_PORT="[대상 컨테이너 SSH 포트]"

# [선택] relay에서 열 포트. 다른 사용자와 겹치지 않게 정합니다.
# TUNNEL_HOST는 수정 불필요합니다.
TUNNEL_HOST="127.0.0.1"
TUNNEL_PORT="44013"

# [필수 수정] 원격 사용자와 relay의 Conda
REMOTE_USER="[컨테이너 SSH 사용자명]"
SOURCE_CONDA_ROOT="[relay conda 루트 절대경로]"
CONDA_PACK_BIN="[relay conda-pack 실행파일 절대경로]"

# [선택] relay의 압축본 보관 경로. 기본값은 수정 불필요
LOCAL_ARCHIVE_DIR="/home/$RELAY_USER/conda-env-archives"

# [수정 불필요] 현재 클러스터의 고정 경로와 다를 때만 변경
REMOTE_ARCHIVE_DIR="/my_workspace/env-archives"
REMOTE_CONDA_ROOT="/home/$REMOTE_USER/anaconda"

# [선택] 배포 후 import 검사. 쉼표로 여러 개 지정하며, 빈 값이면 생략
SMOKE_IMPORTS="torch"
```

relay에서 경로를 확인할 때:

```bash
conda info --base
command -v conda-pack
```

컨테이너 포트가 바뀌면 일반적으로 `CLUSTER_PORT`와 `TUNNEL_PORT`만 변경합니다.

## 4. 배포

### 4.1 Windows에서 터널 열기

설정 검사:

```powershell
.\open-tunnel.ps1 -ValidateOnly
```

터널 실행:

```powershell
.\open-tunnel.ps1
```

이 PowerShell 창은 배포가 끝날 때까지 열어 둡니다. `Ctrl+C`로 터널을 닫습니다.

### 4.2 Relay에서 환경 배포

relay의 다음 환경을 배포한다고 가정합니다.

```text
$SOURCE_CONDA_ROOT/envs/testconn
```

실행:

```bash
cd ~/offline-wheel-bridge
./deploy-conda-env.sh testconn
```

스크립트가 자동으로 수행합니다.

1. `conda-pack`으로 환경 압축
2. SHA-256 생성
3. 역방향 터널을 통해 `/my_workspace/env-archives`로 전송
4. 컨테이너의 임시 staging 경로에 압축 해제
5. `~/anaconda/envs/testconn`으로 배치 후 `conda-unpack`
6. Python, pip 및 `SMOKE_IMPORTS` 검증
7. 실패하면 불완전한 환경 제거 및 기존 환경 복원

컨테이너에서 사용:

```bash
source "$HOME/anaconda/etc/profile.d/conda.sh"
conda activate testconn
```

## 5. 기존 환경 교체와 예외

같은 이름의 환경이 있으면 기본적으로 중단합니다.

```bash
./deploy-conda-env.sh testconn
```

기존 환경을 타임스탬프가 붙은 이름으로 백업하고 교체하려면:

```bash
./deploy-conda-env.sh --replace testconn
```

Conda 관리 파일을 pip가 덮어써 `conda-pack`이 실패한 원인을 이미 확인했고, 현재 상태 그대로 옮기려는 경우에만:

```bash
./deploy-conda-env.sh --ignore-missing testconn
```

두 옵션을 함께 사용할 수 있습니다.

```bash
./deploy-conda-env.sh --replace --ignore-missing testconn
```

## 6. 선택: 새 컨테이너에 Miniconda 최초 설치

이미 `$HOME/anaconda/bin/conda`가 있으면 이 절은 실행하지 않습니다.

Windows에서 터널을 먼저 연 뒤, relay에서 다음을 실행합니다. Linux 설치 파일은 relay에서 내려받고 `/my_workspace/miniconda_installer`에 한 번 보관합니다.

```bash
cd ~/offline-wheel-bridge
source ./bridge.conf

INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
mkdir -p "$LOCAL_ARCHIVE_DIR/miniconda_installer"
curl -fL \
  "https://repo.anaconda.com/miniconda/$INSTALLER" \
  -o "$LOCAL_ARCHIVE_DIR/miniconda_installer/$INSTALLER"

SSH_CMD="ssh -p $TUNNEL_PORT -o ServerAliveInterval=30"
REMOTE="$REMOTE_USER@$TUNNEL_HOST"

$SSH_CMD "$REMOTE" "mkdir -p /my_workspace/miniconda_installer"
rsync -ah --partial --info=progress2 \
  -e "$SSH_CMD" \
  "$LOCAL_ARCHIVE_DIR/miniconda_installer/$INSTALLER" \
  "$REMOTE:/my_workspace/miniconda_installer/"

$SSH_CMD "$REMOTE" \
  "test -x '$REMOTE_CONDA_ROOT/bin/conda' || \
   bash '/my_workspace/miniconda_installer/$INSTALLER' -b -p '$REMOTE_CONDA_ROOT'"

$SSH_CMD "$REMOTE" \
  "'$REMOTE_CONDA_ROOT/bin/conda' init bash && \
   '$REMOTE_CONDA_ROOT/bin/conda' config --set auto_activate true"
```

SSH에 다시 접속하면 base 자동 활성화가 적용됩니다. 로그인 셸이 `.bashrc`를 읽지 않으면 컨테이너에서 한 번 실행합니다.

```bash
touch ~/.bash_profile
grep -qxF '[[ -f ~/.bashrc ]] && source ~/.bashrc' ~/.bash_profile || \
  printf '\n[[ -f ~/.bashrc ]] && source ~/.bashrc\n' >> ~/.bash_profile
```

## 7. 운영 원칙

- Windows의 터널 창은 배포가 끝날 때까지 닫지 않습니다.
- 환경 압축본은 공유 `/my_workspace`에 두고, 실행 환경은 컨테이너 로컬 `~/anaconda/envs`에 둡니다.
- 다른 컨테이너로 배포할 때는 해당 컨테이너의 `CLUSTER_PORT`와 별도의 `TUNNEL_PORT`를 사용합니다.
- `bridge.conf`, SSH 개인키, 비밀번호는 Git에 커밋하지 않습니다.
- 배포 중단 후에는 staging 디렉터리를 임의로 활성화하지 않습니다.
