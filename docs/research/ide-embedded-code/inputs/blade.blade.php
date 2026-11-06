<div>
<p>{{   $a+$b   }}</p>
<p>{!!   strtoupper( $x )   !!}</p>
@if(   $a==1&&$b   )
<span>{{ $user->name( 1,2 ) }}</span>
@endif
@foreach($items   as   $i=>$item)
<li>{{$item}}</li>
@endforeach
@php
$x=1;
if($x){
$y=2;
}
@endphp
<?php
if($z){
$w=3;
}
?>
</div>
