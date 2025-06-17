BACKUP=AccountViewController.m.before_edit
sed -i '' -e '3878,3882s/\(.*heightAnchor.*\),/\1/' -e '3882,3883d' AccountViewController.m
