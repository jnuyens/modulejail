# tests/fixtures/opensuse/Dockerfile
FROM opensuse/tumbleweed:latest
RUN zypper --non-interactive in ShellCheck findutils gawk diffutils && zypper clean -a
COPY modulejail /usr/local/bin/modulejail
RUN chmod +x /usr/local/bin/modulejail
COPY tests/lib /tests/lib
WORKDIR /tests
CMD ["sh", "/tests/lib/run-in-fixture.sh", "opensuse"]
