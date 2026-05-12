# tests/fixtures/arch/Dockerfile
FROM archlinux:latest
RUN pacman -Sy --noconfirm shellcheck diffutils && pacman -Scc --noconfirm
COPY modulejail /usr/local/bin/modulejail
RUN chmod +x /usr/local/bin/modulejail
COPY tests/lib /tests/lib
WORKDIR /tests
CMD ["sh", "/tests/lib/run-in-fixture.sh", "arch"]
