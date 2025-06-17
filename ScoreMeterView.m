// ScoreMeterView.m
#import "ScoreMeterView.h"

@implementation ScoreMeterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _score = 0;
        _scoreLabel = @"Score";
    }
    return self;
}

- (void)setScore:(NSInteger)score {
    _score = MAX(0, MIN(100, score));
    [self setNeedsDisplay];
}

- (void)setScoreLabel:(NSString *)scoreLabel {
    _scoreLabel = [scoreLabel copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat lineWidth = 18.0;
    CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0 - lineWidth;
    CGPoint center = CGPointMake(rect.size.width/2.0, rect.size.height/2.0);
    CGFloat startAngle = -M_PI * 0.75;
    CGFloat endAngle = M_PI * 0.75;
    CGFloat percent = self.score / 100.0;
    CGFloat scoreAngle = startAngle + (endAngle - startAngle) * percent;

    // Draw background arc
    CGContextSetLineWidth(ctx, lineWidth);
    CGContextSetStrokeColorWithColor(ctx, [UIColor systemGray5Color].CGColor);
    CGContextAddArc(ctx, center.x, center.y, radius, startAngle, endAngle, 0);
    CGContextStrokePath(ctx);

    // Draw score arc (color changes by score)
    UIColor *arcColor;
    if (self.score < 40) arcColor = [UIColor systemGreenColor];
    else if (self.score < 70) arcColor = [UIColor systemOrangeColor];
    else arcColor = [UIColor systemRedColor];
    CGContextSetStrokeColorWithColor(ctx, arcColor.CGColor);
    CGContextAddArc(ctx, center.x, center.y, radius, startAngle, scoreAngle, 0);
    CGContextStrokePath(ctx);

    // Draw score text
    NSString *scoreText = [NSString stringWithFormat:@"%ld", (long)self.score];
    UIFont *scoreFont = [UIFont boldSystemFontOfSize:32];
    CGSize scoreSize = [scoreText sizeWithAttributes:@{NSFontAttributeName: scoreFont}];
    [scoreText drawAtPoint:CGPointMake(center.x - scoreSize.width/2, center.y - scoreSize.height/2 - 12)
            withAttributes:@{NSFontAttributeName: scoreFont, NSForegroundColorAttributeName: arcColor}];
    
    // Draw label text
    UIFont *labelFont = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    CGSize labelSize = [self.scoreLabel sizeWithAttributes:@{NSFontAttributeName: labelFont}];
    [self.scoreLabel drawAtPoint:CGPointMake(center.x - labelSize.width/2, center.y + scoreSize.height/2 + 2)
            withAttributes:@{NSFontAttributeName: labelFont, NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
}

@end
