package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/gorilla/mux"
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
	router := mux.NewRouter().StrictSlash(true)
	static := http.FileServer(http.Dir("static"))

	// git plugins
	plugins = make(map[string]string)
	plugins["/com/github"] = "github.com"
	for k, v := range plugins {
		router.PathPrefix(k).Handler(handleArtifact{prefix: k, value: v})
	}

	// api
	api := router.PathPrefix("/api").Subrouter()
	api.HandleFunc("/repositories", apiListRepositories)
	api.HandleFunc("/info/{artifact}", apiInfo)
	api.HandleFunc("/search/{input}", apiSearch)

	// static website
	router.PathPrefix("/").Handler(static)

	// run server
	http.ListenAndServe(":"+PORT, router)
}

type Artifact struct {
	ProjectName  string
	GroupId      string
	ArtifactName string
	Version      string
	BuildFile    string
	PomFile      string
}

func apiSearch(w http.ResponseWriter, r *http.Request) {
	params := mux.Vars(r)
	input := params["input"]
	var artifacts = listArtifactID(ARTIFACT_ROOT)
	var onlyMatchingArtifact = make([]Artifact, 0, len(artifacts))
	for v := range artifacts {
		if strings.Contains(artifacts[v].PomFile, input) {
			onlyMatchingArtifact = append(onlyMatchingArtifact, artifacts[v])
		}
	}
	artifactsJSON, _ := json.MarshalIndent(onlyMatchingArtifact, "", " ")
	w.Write(artifactsJSON)
	return
}

func apiInfo(w http.ResponseWriter, r *http.Request) {
	params := mux.Vars(r)
	artifact := params["artifact"]
	var artifacts = listArtifactBuild(ARTIFACT_ROOT, artifact)
	artifactsJSON, _ := json.MarshalIndent(artifacts, "", " ")
	w.Write(artifactsJSON)
	return
}

func apiListRepositories(w http.ResponseWriter, r *http.Request) {
	var artifacts = listArtifactID(ARTIFACT_ROOT)
	artifactsJSON, _ := json.MarshalIndent(artifacts, "", " ")
	w.Write(artifactsJSON)
	return
}

type handleArtifact struct {
	prefix string
	value  string
}

func (h handleArtifact) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var path = r.URL.Path
	fmt.Println("artifact> GET " + path)

	var relative_path = strings.TrimPrefix(path, h.prefix)
	var remote = "git@" + h.value + ":"
	var tokens = strings.Split(relative_path, "/")
	var version = tokens[len(tokens)-2]
	var artifactId = tokens[len(tokens)-3]
	var repository_part = strings.Join(tokens[:len(tokens)-3], "/")
	var artifact_part = strings.Join(tokens[len(tokens)-3:], "/")

	var git = remote + repository_part + ".git"
	var groupId = strings.Replace(h.prefix[1:], "/", ".", -1) + strings.Replace(repository_part, "/", ".", -1)
	var artifact = groupId + ":" + artifactId + ":" + version
	var artifact_location = strings.Replace(groupId, ".", "/", -1) + "/" + artifact_part
	var artifact_real_location = ARTIFACT_ROOT + "/" + artifact_location

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
		fmt.Println("running builder for: " + artifactId + "( " + git + " version:" + version + ")")
		cmd := exec.Command("/usr/bin/perl", "./scripts/build_artifact.perl", git, groupId, version, artifactId)
		cmdOutput := &bytes.Buffer{}
		cmd.Stdout = cmdOutput
		cmd.Run()
	}

	if _, err := os.Stat(artifact_real_location); err == nil {
		fmt.Println("serving: " + artifact_real_location)
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

func listArtifactBuild(root string, artifact string) []Artifact {
	artifact = strings.Replace(artifact, ".", "/", -1)
	var tokens = strings.Split(artifact, "/")
	var artifactName = tokens[len(tokens)-1]
	var artifacts = listAllArtifact(ARTIFACT_ROOT + "/" + artifact)
	var onlyRequestedArtifact = make([]Artifact, 0, len(artifacts))
	for v := range artifacts {
		if strings.Compare(artifacts[v].ArtifactName, artifactName) == 0 {
			onlyRequestedArtifact = append(onlyRequestedArtifact, artifacts[v])
		}
	}
	return onlyRequestedArtifact
}

func listArtifactID(root string) []Artifact {
	var artifacts = listAllArtifact(ARTIFACT_ROOT)
	var artifactsNoDuplicate = make([]Artifact, 0, len(artifacts))
	var encountered = map[string]bool{}
	for v := range artifacts {
		if !encountered[artifacts[v].ArtifactName] == true {
			encountered[artifacts[v].ArtifactName] = true
			artifactsNoDuplicate = append(artifactsNoDuplicate, artifacts[v])
		}
	}
	return artifactsNoDuplicate
}

func listAllArtifact(root string) []Artifact {
	var artifacts = make([]Artifact, 0)
	filepath.Walk(root,
		func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if strings.HasSuffix(path, ".pom") {
				path = strings.TrimPrefix(path, ARTIFACT_ROOT)
				var pomfile = path
				var tokens = strings.Split(path, "/")
				var version = tokens[len(tokens)-2]
				var libname = tokens[len(tokens)-3]
				var project = tokens[len(tokens)-4]
				var groupID = strings.Join(tokens[1:len(tokens)-3], ".")
				var buildFile = strings.Join(tokens[:len(tokens)-3], "/") + "/build-" + version + ".log"
				var entry = Artifact{project, groupID, libname, version, buildFile, pomfile}
				artifacts = append(artifacts, entry)
			}
			return nil
		})
	return artifacts
}
