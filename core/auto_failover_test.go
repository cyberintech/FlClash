package core
import "testing"

func TestFailedAutoPathTransitions(t *testing.T) {
 tests := []struct{name string; before, after autoPick; want string}{
  {"initial",autoPick{},autoPick{active:true,leaf:"B"},""},
  {"failure",autoPick{active:true,leaf:"A"},autoPick{active:true,leaf:"B",oldExists:true,oldAlive:false},"A"},
  {"healthy failback",autoPick{active:true,leaf:"B"},autoPick{active:true,leaf:"A",oldExists:true,oldAlive:true},""},
  {"manual override",autoPick{active:true,leaf:"A"},autoPick{},""},
  {"resume AUTO",autoPick{},autoPick{active:true,leaf:"B",oldExists:true},""},
  {"profile replacement",autoPick{active:true,leaf:"A"},autoPick{active:true,leaf:"B",oldExists:false},""},
  {"unchanged",autoPick{active:true,leaf:"A"},autoPick{active:true,leaf:"A",oldExists:true},""},
 }
 for _, tt := range tests { t.Run(tt.name,func(t *testing.T){
  s:=failedPathState{previous:tt.before}
  if got:=s.update(tt.after);got!=tt.want {t.Fatalf("got %q, want %q",got,tt.want)}
 }) }
}
func TestOnlyFailedAutoConnectionsAreSelected(t *testing.T) {
 for _, tt := range []struct{chain []string;want bool}{
  {[]string{"A","VPN-AUTO","VPN"},true},
  {[]string{"B","VPN-AUTO","VPN"},false},
  {[]string{"A","VPN"},false},
  {[]string{"DIRECT"},false},
  {nil,false},
 } {if got:=failedPathChain(tt.chain,"A");got!=tt.want {t.Fatalf("chain %v selected=%v",tt.chain,got)}}
}
func TestAutoFailureWatchLifecycleIsIdempotent(t *testing.T) {
 stopAutoFailureWatch()
 startAutoFailureWatch();startAutoFailureWatch()
 autoFailureWatch.Lock();active:=autoFailureWatch.cancel!=nil;autoFailureWatch.Unlock()
 if !active {t.Fatal("watch was not started")}
 stopAutoFailureWatch();stopAutoFailureWatch()
 autoFailureWatch.Lock();active=autoFailureWatch.cancel!=nil;autoFailureWatch.Unlock()
 if active {t.Fatal("watch was not stopped")}
}
