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
    PORT = "8001"
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
  api.HandleFunc("/info/{group}/{artifact}", apiInfo)
  api.HandleFunc("/search/{remote}/{repo}/{artifact}", apiSearch)

  // static website
  router.PathPrefix("/").Handler(static)

  // run server
  http.ListenAndServe(":" + PORT, router)
}

type Artifact struct {
  ProjectName  string
  GroupId      string
  ArtifactName string
  Version      string
  BuildFile    string
}

func apiSearch(w http.ResponseWriter, r *http.Request) {
  /*
  params := mux.Vars(r)
  remote := params["remote"]
  repo := params["repo"]
  artifact := params["artifact"]
  */
}

func apiInfo(w http.ResponseWriter, r *http.Request) {
  params := mux.Vars(r)
  group := params["group"]
  artifact := params["artifact"]

  group = strings.Replace(group, ".", "/", -1)
  var artifacts = listAllArtifact(ARTIFACT_ROOT+"/"+group)

  var onlyRequestedArtifact = make([]Artifact, 0, len(artifacts))
  for v := range artifacts {
    if(strings.Compare(artifacts[v].ArtifactName, artifact) == 0) {
      onlyRequestedArtifact = append(onlyRequestedArtifact, artifacts[v])
    }
  }

  artifactsJson, _ := json.MarshalIndent(onlyRequestedArtifact, "", " ")
  w.Write(artifactsJson)
  return
}

func listAllArtifact(root string) []Artifact {
  var artifacts = make([]Artifact, 0)
  filepath.Walk(root,
      func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        if(strings.HasSuffix(path, ".pom")) {
          path = strings.TrimPrefix(path, ARTIFACT_ROOT)
          var tokens    = strings.Split(path, "/")
          var version   = tokens[len(tokens)-2]
          var libname   = tokens[len(tokens)-3]
          var project   = tokens[len(tokens)-4]
          var groupId   = strings.Join(tokens[1:len(tokens)-3], ".")
          var buildFile = strings.Join(tokens[:len(tokens)-3], "/") + "/build-"+version+".log"
          var entry     = Artifact{project, groupId, libname, version, buildFile}
          artifacts     = append(artifacts, entry)
        }
        return nil
      })
  return artifacts
}

func apiListRepositories(w http.ResponseWriter, r *http.Request) {
  var artifacts = listAllArtifact(ARTIFACT_ROOT)

  var artifactsNoDuplicate = make([]Artifact, 0, len(artifacts))
  var encountered = map[string]bool{}
  for v := range artifacts {
        if !encountered[artifacts[v].ArtifactName] == true {
            encountered[artifacts[v].ArtifactName] = true
            artifactsNoDuplicate = append(artifactsNoDuplicate, artifacts[v])
        }
    }

  artifactsJson, _ := json.MarshalIndent(artifactsNoDuplicate, "", " ")
  w.Write(artifactsJson)
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
  }

  if  _, err := os.Stat(artifact_real_location); err == nil {
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
