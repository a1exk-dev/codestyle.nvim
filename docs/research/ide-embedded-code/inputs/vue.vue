<template>
<div>
<p v-if="a&&b">x</p>
<my-comp :prop="a+b" :obj="{a:1,b:2}" @click="count++;emit( 'x',1 )"></my-comp>
<button @click="if(ok){go( 1,2 )}">go</button>
<span v-for="(item,i) in items" :key="item.id">{{item.name}}</span>
<p :class="{
active:isActive,
'text-danger':hasError
}">y</p>
</div>
</template>

<script>
export default {
data() {
return {a: 1}
}
}
</script>
