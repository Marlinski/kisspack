FROM golang:alpine

ADD ./src /go/src/app
WORKDIR /go/src/app

RUN go get github.com/gorilla/mux
RUN go get github.com/gorilla/mux

ENV PORT=8001

CMD ["go", "run", "main.go"]
