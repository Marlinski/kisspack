package main
import (
  "bytes"
  "fmt"
  "net/http"
  "os"
  "os/exec"
  "strings"
  "io/ioutil"
  "github.com/gorilla/mux"
  "encoding/json"
  "path/filepath"
)

var plugins map[string]string
var ARTIFACT_ROOT string


func main() {
  var PORT string

  if PORT = os.Getenv("PORT"); PORT == "" {
    PORT = "3001"
  }
  if ARTIFACT_ROOT = os.Getenv("PORT"); ARTIFACT_ROOT == "" {
    ARTIFACT_ROOT = "artifact"
  }

  // create http router
  router:=mux.NewRouter().StrictSlash(true)
  static := http.FileServer(http.Dir("static"))

  // git plugins
  plugins = make(map[string]string)
  plugins["/com/github"] = "github.com"
  plugins["/lotd"] = "code.leftofthedot.com"
  for k, v := range plugins {
    router.PathPrefix(k).Handler(handleArtifact{prefix: k, value: v})
  }

  // api
  api := router.PathPrefix("/api").Subrouter()
  api.HandleFunc("/repositories", apiListRepositories)

  // static website
  router.PathPrefix("/").Handler(static)

  // run server
  http.ListenAndServe(":" + PORT, router)
}

func apiListRepositories(w http.ResponseWriter, r *http.Request) {
  var artifacts = make([]map[string]string, 0)

  err := filepath.Walk("./artifact/",
      func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        if(strings.HasSuffix(path, ".pom")) {
          var tokens = strings.Split(path, "/")
          var libname = tokens[len(tokens)-3]
          var version = tokens[len(tokens)-2]
          var groupId = strings.Join(tokens[:len(tokens) - 3], ".")
          var entry = make(map[string]string)
          entry["groupId"] = groupId
          entry["artifactName"] = libname+":"+version
          artifacts = append(artifacts, entry)
        }
        return nil
      })

  if err != nil {
    artifactsJson, _ := json.MarshalIndent(artifacts, "", " ")
    w.Write(artifactsJson)
  } else {
    artifactsJson, _ := json.MarshalIndent(artifacts, "", " ")
    w.Write(artifactsJson)
  }

  return
}

type handleArtifact struct {
  prefix string
  value  string
}

func (h handleArtifact) ServeHTTP(w http.ResponseWriter, r *http.Request) {
  var path = r.URL.Path
  fmt.Println("artifact> GET "+path)

  var relative_path = strings.TrimPrefix(path, h.prefix)
  var remote = "git@"+h.value+":"
  var tokens = strings.Split(relative_path, "/")
  var version = tokens[len(tokens)-2]
  var artifactId = tokens[len(tokens)-3]
  var repository_part = strings.Join(tokens[:len(tokens) - 3], "/")
  var artifact_part = strings.Join(tokens[len(tokens) - 3:], "/")

  var git = remote+repository_part+".git"
  var groupId = strings.Replace(h.prefix[1:], "/", ".", -1)+strings.Replace(repository_part,"/",".", -1)
  var artifact = groupId+":"+artifactId+":"+version
  var artifact_location = strings.Replace(groupId, ".", "/", -1)+"/"+artifact_part
  var artifact_real_location = ARTIFACT_ROOT+"/"+artifact_location

  /*
  fmt.Println("relative_path="+relative_path)
  fmt.Println("artifact_location="+artifact_location)
  fmt.Println("artifact_real_location="+artifact_real_location)
  fmt.Println("remote="+remote)
  fmt.Println("version="+version)
  fmt.Println("artifactId="+artifactId)
  fmt.Println("repository="+repository_part)
  fmt.Println("git="+git)
  fmt.Println("groupId="+groupId)
  fmt.Println("artifact="+artifact)
  */

  if _, err := os.Stat(artifact_real_location); os.IsNotExist(err) {
    fmt.Println("running builder for: "+artifactId+"( "+git+" version:"+version+")")
    cmd := exec.Command("/usr/bin/perl", "./scripts/build_artifact.perl", git, groupId, version, artifactId)
    cmdOutput := &bytes.Buffer{}
    cmd.Stdout = cmdOutput
    cmd.Run()
  } else {
      fmt.Println("serving artifact: "+artifact_real_location)
      data, err := ioutil.ReadFile(string(artifact_real_location))

      if err == nil {
        w.Header().Set("Artifact", artifact)
        w.Write(data)
        } else {
          w.WriteHeader(404)
          w.Write([]byte("404 Something went wrong - " + http.StatusText(404)))
        }
      }
      return
    }
