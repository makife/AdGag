import "package:flutter/material.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";

/// Short, brand-first onboarding (CLAUDE.md section 36). No tutorial
/// screens for SOLD/AD THIS — those are taught contextually in the feed
/// (section 36/63), not here.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_OnboardingSlide> _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      title: "AdGag",
      subtitle: "The social network where everything is an ad.",
      useLogoImage: true,
    ),
    _OnboardingSlide(title: "Pick anything.", subtitle: "A rock. Your coffee. Yourself. Monday."),
    _OnboardingSlide(title: "Sell it in 10 seconds.", subtitle: "Short, punchy, funny. That's the format."),
    _OnboardingSlide(title: "See it. Ad it. Go.", subtitle: "Watch an ad. Make a better one. Publish."),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _slides.length - 1) {
      context.pushReplacementTo(RoutePaths.signUp);
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: TextButton(
                  onPressed: () => context.pushReplacementTo(RoutePaths.signUp),
                  child: const Text("Skip"),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (int i) => setState(() => _page = i),
                itemBuilder: (BuildContext context, int i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(
                      _slides.length,
                      (int i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? AppColors.gradientPink : Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_page == _slides.length - 1 ? "Get started" : "Next"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({required this.title, required this.subtitle, this.useLogoImage = false});
  final String title;
  final String subtitle;

  /// True only for the brand-name slide — shows the actual
  /// assets/branding/AdGag.png lockup instead of recreating the "AdGag"
  /// wordmark with a TextStyle/ShaderMask approximation. Other slides'
  /// titles are onboarding copy, not the brand wordmark, so they stay text.
  final bool useLogoImage;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (slide.useLogoImage)
            Image.asset("assets/branding/AdGag.png", width: 220)
          else
            ShaderMask(
              shaderCallback: (Rect bounds) => AppColors.brandGradient.createShader(bounds),
              child: Text(
                slide.title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(color: Colors.white),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(slide.subtitle, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
