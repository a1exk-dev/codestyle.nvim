<?php $title = 'x'; ?>
<html>
<head>
    <style>
      body {
        margin: 0
      }

      .a {
        color: red
      }
    </style>
    <script>
            function f(a, b) {
                    if (a) {
                            return b;
                    }
            }
    </script>
</head>
<body>
<?php if ($title): ?>
    <p><?= $title ?></p>
<?php endif; ?>
</body>
</html>
