<?php
$html = <<<HTML
<div>
<p>{$x}</p>
<span>text</span>
</div>
HTML;
$sql = <<<SQL
select a,b from t where a=1 and b=2
SQL;
$js2 = <<<JS
function g(a,b){
return a+b;
}
JS;
// language=JavaScript
$js = "function f(a,b){return a+b;}";
// language=CSS
$css = 'a{color:red;margin:0}';
// language=HTML
$frag = '<div><p>x</p></div>';
if($x){
$y=1;
}
