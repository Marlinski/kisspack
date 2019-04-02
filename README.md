# kisspack - keep it simple stupid packager

kisspack is a simple yet capable maven repository pretty similar to jitpack. It can automatically pull project from a git repository and 
generate the artifacts.

## running the repository

### kisspack dependencies

The Dockerfile is still a work in progress, currently kisspack required the following dependencies:

* golang
* perl
* bash tools (find, sed, etc..)

### start the repo

to start the repository, just clone the project then cd into it and run the following go command:

```bash
$ go run src/main.go
```

The maven repository is now listening on port 8001 (by default). You can change the listening port by modifyin the environment variable PORT

## gradle configuration

### add maven repository

In your gradle project, add in your build.gradle at the end of repositories:

```gradle
repositories {
    ...
    maven { url 'http://127.0.0.1:8001' }
}
```

### add your dependencies

then add a dependency:

```gradle
dependencies {
   implementation 'com.github.Marlinski.Terra.libdtn:libdtn-client-api:f35e1ac192'
}
```

### pattern

the dependency must follow the following pattern:

```
   implementation '<REMOTE>.<REPO>:<LIBRARY>:<COMMIT>'
```

There are only one remote available at the moment:

| REMOTE  | Description |
| ------------- | ------------- |
| com.github | git@github.com:  |




