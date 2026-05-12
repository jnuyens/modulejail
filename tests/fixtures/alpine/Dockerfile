# tests/fixtures/alpine/Dockerfile
FROM alpine:latest
RUN apk add --no-cache shellcheck
COPY modulejail /usr/local/bin/modulejail
RUN chmod +x /usr/local/bin/modulejail
COPY tests/lib /tests/lib
WORKDIR /tests
CMD ["sh", "/tests/lib/run-in-fixture.sh", "alpine"]
