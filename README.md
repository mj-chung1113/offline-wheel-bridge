# Offline Wheel Bridge

인터넷이 차단된 GPU 클러스터에 Python wheel 또는 conda 환경 전체를 SSH로 반입하는 소형 도구 모음입니다.

- 인터넷 연결 서버에서 패키지와 의존성 다운로드
- Windows PC를 통한 reverse SSH tunnel
- 공유 NFS wheelhouse로 증분 동기화
- `conda-pack` 환경 전체 패킹, 체크섬 검증, 재배치
- 여러 컨테이너에서 공유 wheelhouse 사용
- 새 Bash SSH 세션의 conda 초기화

설치 및 운영 방법은 [한국어 상세 문서](README_KO.md)를 참고하세요.

이 도구는 관리자의 네트워크 정책을 우회하는 프록시가 아닙니다. 허가된 패키지 파일과 환경 아카이브를 SSH로 반입하는 오프라인 배포 도구입니다.
