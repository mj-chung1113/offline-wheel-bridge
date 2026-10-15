# Offline Wheel Bridge

인터넷이 되는 릴레이 서버에서 Python 패키지를 내려받고, Windows PC의 역방향 SSH 터널을 통해 인터넷이 차단된 GPU 클러스터의 공유 NFS로 옮기는 도구입니다.

전체 PyPI 미러가 아니라 실제로 요청한 패키지만 누적하는 `wheelhouse` 방식입니다. 암호와 개인키는 저장하지 않으며 SSH가 필요할 때 직접 묻거나 기존 SSH agent를 사용합니다.

## 구성

```text
PyPI -> 릴레이 서버 wheelhouse
            |
            | Windows PC의 reverse SSH tunnel
            v
      클러스터 공유 NFS wheelhouse
            |
            +-- 컨테이너 A
            +-- 컨테이너 B
```

## 1. 파일 배치

이 디렉터리를 릴레이 서버에 복사하고 실행 권한을 줍니다.

```bash
chmod +x *.sh
cp bridge.env.example bridge.env
```

`bridge.env`에서 Python 경로, 계정, 포트와 wheelhouse 경로를 수정합니다. `bridge.env`에는 암호나 개인키를 넣지 않습니다.

## 2. Windows PC에서 터널 열기

PowerShell에서 실행합니다.

```powershell
.\open-reverse-tunnel.ps1
```

다른 사용자나 서버는 매개변수로 바꿀 수 있습니다.

```powershell
.\open-reverse-tunnel.ps1 `
  -RelayUser relay_user `
  -RelayHost relay.example.edu `
  -ClusterHost cluster.internal `
  -ClusterPort 40000 `
  -RemotePort 44000
```

PowerShell 창은 동기화가 끝날 때까지 열어 둡니다. 이 스크립트는 먼저 클러스터 SSH 포트가 PC에서 접근 가능한지 확인합니다.

## 3. 릴레이 서버에서 다운로드하고 동기화

개별 패키지:

```bash
./bridge.sh einops==0.8.1 accelerate==1.10.1
```

요구사항 파일:

```bash
./bridge.sh -r requirements-extra.txt
```

`bridge.sh`는 다음을 순서대로 수행합니다.

1. 설정된 Python으로 패키지와 의존성을 `SOURCE_WHEELHOUSE`에 다운로드
2. SHA-256 목록 갱신
3. `rsync --partial`로 새 파일만 클러스터 공유 NFS에 전송

다운로드와 동기화를 따로 실행할 수도 있습니다.

```bash
./download-wheels.sh -r requirements-extra.txt
./sync-wheelhouse.sh
```

### 패키지 버전

버전을 생략하면 다운로드 시점에 릴레이 Python과 호환되는 최신 버전을 선택합니다. 연구 재현성을 위해 실제 실험에 사용하는 패키지는 `==`로 고정하는 것을 권장합니다.

```bash
./bridge.sh einops==0.8.1 accelerate==1.10.1
```

버전을 탐색한 뒤에는 클러스터의 최종 환경을 기록합니다.

```bash
python -m pip freeze > requirements-lock.txt
```

기존 환경의 의존성을 그대로 사용하고 요청한 패키지만 받을 때는 `--no-deps`를 사용할 수 있지만, 필요한 의존성이 없으면 오프라인 설치 또는 실행이 실패합니다.

```bash
./bridge.sh --no-deps einops==0.8.1
```

## 4. 클러스터에서 오프라인 설치

목표 가상환경을 활성화한 뒤 실행합니다.

```bash
./install-offline.sh einops==0.8.1
```

특정 Python을 명시할 수도 있습니다.

```bash
PYTHON_BIN=/opt/research-env/bin/python \
  ./install-offline.sh -r requirements-extra.txt
```

설치 전에 `SHA256SUMS`를 검증하고, `--no-index`로 외부 접속 없이 공유 wheelhouse만 사용합니다.

## 5. conda 환경 전체 복사

패키지 몇 개가 아니라 동작 중인 conda 환경 전체를 복제해야 할 때 사용합니다. 릴레이 서버의 `bridge.env`에서 다음 값을 먼저 확인합니다.

```bash
SOURCE_ENV_PREFIX=/opt/conda/envs/research
CONDA_PACK_BIN=/opt/conda/bin/conda-pack
SOURCE_ENV_ARCHIVE_DIR=/srv/offline-wheel-bridge/env-archives
ENV_ARCHIVE_NAME=research-env.tar.gz
TARGET_ENV_ARCHIVE_DIR=/shared/offline-wheel-bridge/env-archives
```

Windows PC에서 역방향 터널을 열어 둔 상태로, 릴레이 서버에서 패킹과 전송을 한 번에 실행합니다.

```bash
./bridge-environment.sh
```

따로 실행할 수도 있습니다.

```bash
./pack-environment.sh
./sync-environment.sh
```

스크립트는 다음을 수행합니다.

1. `conda-pack`으로 활성 여부와 무관하게 `SOURCE_ENV_PREFIX` 전체를 패킹
2. 완성 전 파일에는 `.partial.PID` 이름을 사용하여 불완전한 압축본 노출 방지
3. SHA-256 체크섬 생성
4. `rsync --partial`로 공유 NFS의 `TARGET_ENV_ARCHIVE_DIR`에 전송

정상 환경에서 `conda-pack` 오류를 무시하지 않습니다. 과거에 pip가 conda 관리 파일을 덮어쓴 환경처럼 원인을 확인한 경우에만 `bridge.env`에서 아래 값을 사용합니다.

```bash
PACK_IGNORE_MISSING=1
```

클러스터에서는 공유 NFS의 압축본을 각 컨테이너의 로컬 `overlay`로 풉니다.

```bash
./unpack-environment.sh \
  /shared/offline-wheel-bridge/env-archives/research-env.tar.gz \
  "$HOME/envs/research-env"
```

이 스크립트는 체크섬을 검증하고 압축을 푼 뒤 `conda-unpack`으로 경로를 재배치합니다. 기존의 비어 있지 않은 환경 디렉터리는 절대 덮어쓰지 않습니다. 실행할 때는 conda 자체가 없어도 됩니다.

```bash
export CUDA_VISIBLE_DEVICES=0
"$HOME/envs/research-env/bin/python" -V
```

환경 압축본은 공유 NFS에 한 번만 저장하고, 실행 환경은 컨테이너별 로컬 경로에 푸는 것을 권장합니다. NFS에 환경을 직접 풀면 작은 파일 메타데이터 접근 때문에 느릴 수 있고, 여러 컨테이너에서 동시에 수정할 위험이 있습니다.

## 6. Conda를 새 SSH 셸에서 자동 활성화

Conda가 `$HOME/anaconda3`에 설치된 컨테이너에서는 다음을 한 번 실행합니다.

```bash
./enable-conda-shell.sh
```

다른 위치라면 conda 루트를 인자로 줍니다.

```bash
./enable-conda-shell.sh /opt/conda
```

내부적으로 `conda init bash`와 `conda config --set auto_activate_base true`를 실행합니다. SSH를 다시 접속하거나 다음을 실행하면 적용됩니다.

```bash
source ~/.bashrc
```

자동 `(base)` 활성화를 나중에 끄려면:

```bash
conda config --set auto_activate_base false
```

`conda init`은 해당 사용자의 `~/.bashrc`를 수정하므로 컨테이너별 홈이 분리되어 있으면 각 컨테이너에서 한 번씩 실행해야 합니다. 비대화형 배치 작업은 셸 초기화에 의존하지 말고 환경의 Python 절대경로를 사용하는 것이 안전합니다.

## 다른 사용자가 쓸 때

- 사용자마다 자신의 `bridge.env`를 만듭니다.
- 터널 포트가 겹치지 않도록 `TARGET_TUNNEL_PORT`와 PowerShell의 `RemotePort`를 같은 값으로 바꿉니다.
- 클러스터의 공유 경로에 쓰기 권한이 있어야 합니다.
- 여러 사용자가 같은 wheelhouse에 동시에 동기화하거나 설치 중 파일을 갱신하지 않는 것이 안전합니다.
- 공개키 인증을 사용하면 암호 입력을 줄일 수 있지만, 개인키를 공유 NFS나 저장소에 커밋하지 않습니다.

## 호환성 주의

릴레이 서버의 다운로드용 Python은 목표 환경과 Python major/minor 및 ABI가 같아야 합니다.

- 순수 Python 및 공식 manylinux wheel은 일반적으로 안전합니다.
- source distribution은 클러스터에서 C/C++ 빌드 도구를 요구할 수 있습니다.
- RTX 4090에서 직접 컴파일한 CUDA 확장 wheel을 H100에 복사하지 않습니다.
- H100 CUDA 확장은 `sm_90`과 적합한 CUDA toolkit이 있는 클러스터 devel 환경에서 빌드해야 합니다.
- `BINARY_ONLY=1`로 설정하면 공식 binary wheel이 없는 패키지를 초기에 실패시킬 수 있습니다.
- 패킹한 환경도 호스트 NVIDIA 드라이버와 GPU 아키텍처의 호환성을 자동으로 보장하지 않습니다. 이전 후 CUDA smoke test를 수행합니다.

## 운영 범위

이 도구는 관리자의 네트워크 제한을 우회하는 일반 인터넷 프록시가 아닙니다. 사용자가 요청한 패키지 파일만 SSH로 반입하는 오프라인 배포 도구입니다. 조직 정책과 라이선스를 확인한 뒤 사용하세요.
