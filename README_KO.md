# Offline Wheel Bridge

인터넷이 되는 relay 서버에서 Python 패키지 또는 conda 환경을 준비하고, Windows PC의 역방향 SSH 터널을 통해 인터넷이 차단된 GPU 클러스터의 공유 저장소로 옮기는 도구입니다.

전체 PyPI를 복제하지 않고 실제로 요청한 패키지만 누적합니다. 암호와 개인키는 설정 파일에 저장하지 않으며 SSH가 필요할 때 직접 입력하거나 기존 SSH agent를 사용합니다.

```text
PyPI -> relay 서버 wheelhouse
              |
              | Windows PC의 reverse SSH tunnel
              v
       클러스터 공유 wheelhouse
              |
              +-- 컨테이너 A
              +-- 컨테이너 B
```

## 1. 한 번만 설정할 파일

저장소를 받은 뒤 예시 파일을 복사합니다.

```bash
git clone https://github.com/mj-chung1113/offline-wheel-bridge.git
cd offline-wheel-bridge
cp bridge.conf.example bridge.conf
chmod +x *.sh
```

이제 **`bridge.conf` 하나만 수정**합니다. Windows의 `open-reverse-tunnel.ps1`과 relay 서버의 모든 Bash 스크립트가 같은 키를 읽습니다.

```bash
RELAY_USER="[relay 서버 사용자명]"
RELAY_HOST="[relay 서버 IP 주소 또는 도메인]"
CLUSTER_HOST="[클러스터 서버 IP 주소 또는 도메인]"
CLUSTER_PORT="[클러스터 SSH 포트]"

TARGET_TUNNEL_HOST="127.0.0.1"
REVERSE_TUNNEL_PORT="44000"

TARGET_SSH_USER="[클러스터 사용자명]"
TARGET_WHEELHOUSE="[클러스터 공유 wheelhouse 절대경로]"
TARGET_ENV_ARCHIVE_DIR="[클러스터 공유 환경 압축본 절대경로]"

PYTHON_BIN="[relay 서버 Python 실행파일 절대경로]"
SOURCE_WHEELHOUSE="[relay 서버 wheelhouse 절대경로]"

SOURCE_ENV_PREFIX="[복사할 conda 환경 절대경로]"
CONDA_PACK_BIN="[conda-pack 실행파일 절대경로]"
SOURCE_ENV_ARCHIVE_DIR="[relay 서버 환경 압축본 저장 절대경로]"
ENV_ARCHIVE_NAME="research-env.tar.gz"
```

설정 의미:

| 설정 | 입력할 값 |
|---|---|
| `RELAY_USER` | 인터넷이 되는 relay 서버의 사용자명 |
| `RELAY_HOST` | relay 서버의 IP 주소 또는 도메인 |
| `CLUSTER_HOST` | Windows PC에서 접근 가능한 클러스터 주소 |
| `CLUSTER_PORT` | 대상 컨테이너의 SSH 포트 |
| `TARGET_TUNNEL_HOST` | relay 서버에서 보이는 터널 주소. 보통 `127.0.0.1` 유지 |
| `REVERSE_TUNNEL_PORT` | relay 서버에 열 임시 포트. 다른 사용자와 겹치지 않게 선택 |
| `TARGET_SSH_USER` | 클러스터 SSH 사용자명 |
| `TARGET_WHEELHOUSE` | 클러스터 공유 저장소의 wheel 보관 경로 |
| `TARGET_ENV_ARCHIVE_DIR` | 클러스터 공유 저장소의 환경 압축본 경로 |
| `PYTHON_BIN` | relay 서버에서 wheel을 받을 Python |
| `SOURCE_WHEELHOUSE` | relay 서버의 wheel 누적 경로 |
| `SOURCE_ENV_PREFIX` | 복사할 conda 환경 경로 |
| `CONDA_PACK_BIN` | relay 서버의 `conda-pack` 실행파일 |
| `SOURCE_ENV_ARCHIVE_DIR` | relay 서버의 환경 압축본 생성 경로 |

`bridge.conf`는 `.gitignore`에 포함되어 GitHub에 올라가지 않습니다. 암호, 개인키, API 토큰은 넣지 마세요.

Windows PC와 relay 서버가 서로 다른 clone을 사용한다면 동일한 `bridge.conf`를 양쪽 저장소 디렉터리에 복사해야 합니다. 이후에는 이 파일만 관리하면 됩니다.

## 2. 실행 순서

### Windows PC: 터널 열기

저장소 디렉터리에서 다음만 실행합니다. 접속 주소를 명령행에 다시 적을 필요가 없습니다.

```powershell
.\open-reverse-tunnel.ps1
```

다른 위치의 설정을 사용하려면:

```powershell
.\open-reverse-tunnel.ps1 -ConfigPath C:\secure\bridge.conf
```

네트워크 연결 없이 설정 문법과 필수값만 확인하려면:

```powershell
.\open-reverse-tunnel.ps1 -ValidateOnly
```

스크립트는 `bridge.conf`의 `CLUSTER_HOST:CLUSTER_PORT`를 먼저 검사한 뒤, relay 서버의 `TARGET_TUNNEL_HOST:REVERSE_TUNNEL_PORT`에 역방향 터널을 엽니다. 동기화가 끝날 때까지 PowerShell 창을 열어 둡니다.

### Relay 서버: 도구 저장소 자체를 클러스터로 전송 (최초 1회)

클러스터가 인터넷에 연결되지 않아 GitHub에서 직접 `git clone`할 수 없다면, relay 서버에 받은 저장소를 역방향 터널로 한 번 전송합니다. Windows PC에서 터널을 열어 둔 상태로 relay 서버의 저장소 디렉터리에서 실행합니다.

```bash
source ./bridge.conf
TARGET_TOOLS_DIR="/my_workspace/offline-wheel-bridge"

ssh -p "$REVERSE_TUNNEL_PORT" \
  "$TARGET_SSH_USER@$TARGET_TUNNEL_HOST" \
  "mkdir -p '$TARGET_TOOLS_DIR'"

rsync -az --partial \
  --exclude '.git/' \
  --exclude 'bridge.conf' \
  -e "ssh -p $REVERSE_TUNNEL_PORT" \
  ./ \
  "$TARGET_SSH_USER@$TARGET_TUNNEL_HOST:$TARGET_TOOLS_DIR/"
```

도구 저장소는 여러 컨테이너에서 함께 볼 수 있도록 `/my_workspace/offline-wheel-bridge`에 둡니다. `.git`과 접속 정보가 담긴 `bridge.conf`는 전송하지 않습니다.

클러스터에서는 한 번만 실행 권한을 설정합니다.

```bash
cd /my_workspace/offline-wheel-bridge
chmod +x ./*.sh
```

이후 같은 공유 저장소를 마운트한 컨테이너들은 저장소를 다시 복사하지 않고 같은 스크립트를 사용할 수 있습니다. 저장소가 갱신되면 relay 서버에서 위 `rsync` 명령을 다시 실행하면 변경된 파일만 전송됩니다.

### Relay 서버: 패키지 다운로드와 전송

개별 패키지:

```bash
./bridge.sh einops==0.8.1 accelerate==1.10.1
```

요구사항 파일:

```bash
./bridge.sh -r requirements-extra.txt
```

`bridge.sh`가 다운로드, SHA-256 갱신, `rsync --partial` 동기화를 순서대로 수행합니다. 따로 실행할 수도 있습니다.

```bash
./download-wheels.sh -r requirements-extra.txt
./sync-wheelhouse.sh
```

### 클러스터: 오프라인 설치

목표 가상환경을 활성화한 뒤 실행합니다.

```bash
WHEELHOUSE_DIR="[클러스터 공유 wheelhouse 절대경로]" \
  ./install-offline.sh einops==0.8.1
```

특정 Python을 지정할 수도 있습니다.

```bash
PYTHON_BIN="[목표 Python 실행파일 절대경로]" \
WHEELHOUSE_DIR="[클러스터 공유 wheelhouse 절대경로]" \
  ./install-offline.sh -r requirements-extra.txt
```

설치 전에 체크섬을 검증하며 `--no-index`로 외부 접속 없이 공유 wheelhouse만 사용합니다.

## 3. 패키지 버전

버전을 생략하면 다운로드 시점에 relay Python과 호환되는 최신 버전을 선택합니다. 연구 재현성을 위해 실제 실험 패키지는 `==`로 고정하는 것을 권장합니다.

```bash
./bridge.sh einops==0.8.1
```

최종 환경도 기록합니다.

```bash
python -m pip freeze > requirements-lock.txt
```

기존 의존성을 그대로 사용하고 요청한 패키지만 받을 때는 `--no-deps`를 사용할 수 있지만, 필요한 의존성이 없으면 설치 또는 실행이 실패합니다.

```bash
./bridge.sh --no-deps einops==0.8.1
```

## 4. conda 환경 전체 복사

Windows 터널을 열어 둔 상태로 relay 서버에서 실행합니다.

```bash
./bridge-environment.sh
```

이 명령은 `bridge.conf`의 환경 경로를 읽어 다음을 수행합니다.

1. `conda-pack`으로 `SOURCE_ENV_PREFIX` 전체 패킹
2. `.partial.PID` 파일로 불완전한 압축본 노출 방지
3. SHA-256 체크섬 생성
4. 클러스터의 `TARGET_ENV_ARCHIVE_DIR`로 증분 전송

패킹과 전송을 따로 실행할 수도 있습니다.

```bash
./pack-environment.sh
./sync-environment.sh
```

정상 환경에서는 `PACK_IGNORE_MISSING="0"`을 유지합니다. pip가 conda 관리 파일을 덮어쓴 원인을 확인한 환경에서만 다음을 사용합니다.

```bash
PACK_IGNORE_MISSING="1"
```

클러스터에서는 압축본을 각 컨테이너의 로컬 `overlay`에 풉니다.

```bash
./unpack-environment.sh \
  "[클러스터 공유 환경 압축본 절대경로]/research-env.tar.gz" \
  "[컨테이너 로컬 환경 설치 절대경로]"
```

이 스크립트는 체크섬 검증 후 `conda-unpack`으로 경로를 재배치하며 기존의 비어 있지 않은 디렉터리를 덮어쓰지 않습니다. conda 자체가 없어도 실행할 수 있습니다.

환경 압축본은 공유 저장소에 한 번만 두고, 실행 환경은 컨테이너별 로컬 저장소에 푸는 것을 권장합니다. NFS에 직접 풀면 작은 파일 접근이 느리고 여러 컨테이너가 동시에 수정할 수 있습니다.

## 5. 새 SSH 셸에서 conda 자동 활성화

Conda가 `$HOME/anaconda3`에 설치됐다면:

```bash
./enable-conda-shell.sh
```

다른 위치라면 conda 루트를 전달합니다.

```bash
./enable-conda-shell.sh "[conda 설치 루트 절대경로]"
```

내부적으로 `conda init bash`와 `conda config --set auto_activate_base true`를 실행합니다. SSH에 다시 접속하거나 `source ~/.bashrc`를 실행하면 적용됩니다.

비대화형 배치 작업에서는 셸 초기화에 의존하지 말고 Python 절대경로를 사용하는 것이 안전합니다.

## 6. 다른 사용자가 쓸 때

- 사용자마다 `bridge.conf.example`을 `bridge.conf`로 복사하고 한글 자리표시자만 교체합니다.
- `REVERSE_TUNNEL_PORT`는 relay 서버의 다른 사용자와 겹치지 않게 정합니다.
- 클러스터 공유 경로에 쓰기 권한이 있어야 합니다.
- 같은 wheelhouse에 여러 사용자가 동시에 동기화하지 않는 것이 안전합니다.
- 개인키를 공유 NFS나 Git 저장소에 커밋하지 않습니다.

## 7. 호환성 주의

relay 서버의 Python은 목표 환경과 Python major/minor 및 ABI가 같아야 합니다.

- 순수 Python 및 공식 manylinux wheel은 일반적으로 안전합니다.
- source distribution은 클러스터에서 C/C++ 빌드 도구를 요구할 수 있습니다.
- 한 GPU에서 직접 컴파일한 CUDA 확장 wheel을 다른 GPU 아키텍처에 그대로 복사하지 않습니다.
- 대상 GPU용 CUDA 확장은 적합한 CUDA toolkit이 있는 클러스터 devel 환경에서 빌드합니다.
- `BINARY_ONLY="1"`이면 공식 binary wheel이 없는 패키지를 초기에 실패시킵니다.
- 패킹한 환경도 호스트 NVIDIA 드라이버 및 GPU 아키텍처 호환성을 자동으로 보장하지 않습니다. 이전 후 CUDA smoke test를 수행합니다.

## 운영 범위

이 도구는 관리자의 네트워크 제한을 우회하는 일반 인터넷 프록시가 아닙니다. 허가된 패키지 파일과 환경 압축본을 SSH로 반입하는 오프라인 배포 도구입니다. 조직 정책과 라이선스를 확인한 뒤 사용하세요.
