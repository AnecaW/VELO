import 'package:flutter/material.dart';

abstract final class VeloSpace {
  static const double small = 8, gap = 12, page = 16, section = 24;
  static const insets = EdgeInsets.all(page);
}

class VeloPageList extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  const VeloPageList({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.padding = VeloSpace.insets,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: padding,
          itemCount: children.length,
          separatorBuilder: (_, i) => const SizedBox(height: 12),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    ),
  );
}

class VeloSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const VeloSection({super.key, required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: VeloSpace.section),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 52, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class VeloNotice extends StatelessWidget {
  final String text;
  final bool error;
  const VeloNotice(this.text, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:
          (error
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary)
              .withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(error ? Icons.info_outline : Icons.check_circle_outline, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
