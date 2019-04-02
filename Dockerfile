# We build kisspack in a separate container with development tools
FROM golang:alpine AS builder

# We need to install git for `go mod` to fetch dependencies
RUN apk update && apk add git

ADD ./src /kisspack
WORKDIR /kisspack

RUN go build -o /tmp/kisspack


# Production container is a new one with only what's needed (no development
# tools).
FROM alpine:latest
ENV PORT=8001
EXPOSE 8001

RUN apk update && apk --no-cache add ca-certificates perl

COPY --from=builder /tmp/kisspack ./

CMD ["./kisspack"]
