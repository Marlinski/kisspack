function linkFormatter(value) {
  return '<a href="' + value.href + '">' + value.text + '</a>';
}

$(document).ready(function(){
  $.ajax({
    url:"/api/repositories",
    crossDomain:false,
    dataType:"json",
    success: function(artifactJson) {
             $('#artifactTable').bootstrapTable({
               data: artifactJson
             });
         },
  });
});
