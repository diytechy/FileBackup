# FileBackup portable path key v1. Data comes from the writer's locked Unicode
# libraries. NFD + full case fold + canonical reordering, independent of locale.
function load_path_keys(path,    line, v) {
    while ((getline line < path) > 0) {
        if (substr(line,1,1)=="#") continue
        split(line,v,"\t"); fold[v[1]]=v[2]; combining[v[1]]=v[3]+0
    }
    close(path)
    if (!("A" in fold)) exit 2
}
function path_key(s,    i,j,c,mapped,n,k,out,letters,classes) {
    mapped=""
    for(i=1;i<=length(s);i++) { c=substr(s,i,1); mapped=mapped ((c in fold)?fold[c]:c) }
    n=0
    for(i=1;i<=length(mapped);i++) {
        c=substr(mapped,i,1); k=combining[c]+0; j=++n
        while(k!=0 && j>1 && classes[j-1]>k) { letters[j]=letters[j-1]; classes[j]=classes[j-1]; j-- }
        letters[j]=c; classes[j]=k
    }
    out=""; for(i=1;i<=n;i++)out=out letters[i]
    return out
}
