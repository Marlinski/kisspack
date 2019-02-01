function linkFormatter(value) {
  return '<a href="' + value.href + '">' + value.text + '</a>';
}

function AddArtifactInfoRow() {
  if(! $('#buildSection').length )
  {
    console.log("not exist lah");
    $('#mainColumn').prepend(`
      <div class="row" id="buildSection">
      <h3>Builds</h3>
      <table id="buildTable">
      <thead>
      <th data-field="Version">Build Version</th>
      <th data-field="BuildFile">Log</th>
      <th data-field="Status">Status</th>
      </thead>
      </table>
      </div>
      `);
    } else {
      console.log("exist already");
    }
  }

  function ArtifactInfo(group, artifact) {
    console.log("group="+group+" artifact="+artifact);
    AddArtifactInfoRow()
    $.ajax({
      url:"/api/info/"+group+"/"+artifact,
      crossDomain:false,
      dataType:"json",
      success: function(artifactJson) {
        for (let i = 0; i < artifactJson.length; i++) {
          artifactJson[i]["Version"] = artifactJson[i]["ArtifactName"]+":"+artifactJson[i]["Version"]
          artifactJson[i]["BuildFile"] = '<a href="'+artifactJson[i]["BuildFile"]+'"><i class="fas fa-file fa-2x"></i></a>';
        }
        $('#buildTable').bootstrapTable('destroy');
        $('#buildTable').bootstrapTable({
          data: artifactJson
        });
      },
    });
  }

  function ArtifactIdFormatter(value) {
    var group = value["GroupId"];
    var name = value["ArtifactNameBis"]
    var ret = '<a href="javascript:void(0)" onClick="ArtifactInfo(\''+group+'\',\''+name+'\')">'+name+'</a>';
    return ret;
  }

  $(document).ready(function(){
    $.ajax({
      url:"/api/repositories",
      crossDomain:false,
      dataType:"json",
      success: function(artifactJson) {
        for (let i = 0; i < artifactJson.length; i++) {
          artifactJson[i]["ArtifactNameBis"] = artifactJson[i]["ArtifactName"]
          artifactJson[i]["ArtifactName"] = artifactJson[i]
        }
        $('#artifactTable').bootstrapTable({
          data: artifactJson
        });
      },
    });
  });
