import 'package:flutter/material.dart';
import 'package:agni_college_bus_tracker/theme.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final bool isOutlined;
  final bool isLarge;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.isOutlined = false,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.adminBlue;
    final txtColor = textColor ?? AppColors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLarge ? AppSpacing.xl : AppSpacing.lg,
            vertical: isLarge ? AppSpacing.md + 4 : AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isOutlined ? Colors.transparent : bgColor,
            border: isOutlined ? Border.all(color: bgColor, width: 2) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: isOutlined ? bgColor : txtColor, size: 20),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                text,
                style: context.textStyles.labelLarge?.copyWith(
                  color: isOutlined ? bgColor : txtColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
