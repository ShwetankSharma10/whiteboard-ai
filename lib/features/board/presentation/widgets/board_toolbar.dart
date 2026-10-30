import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/board_object.dart';
import '../providers/board_provider.dart';
import 'board_canvas.dart';

// Miro Signature Drawing Palette
const kPalette = <Color>[
  Color(0xFF1F2937), // Ink / Slate
  Color(0xFF0D54FF), // Miro Electric Blue
  Color(0xFF10B981), // Emerald Green
  Color(0xFFF59E0B), // Miro Amber / Gold
  Color(0xFFEF4444), // Coral Red
  Color(0xFF8B5CF6), // Purple
  Color(0xFF6B7280), // Slate Gray
  Color(0xFFFFFFFF), // Pure White
];

// Miro Official Sticky Note Color Palette
const kStickyNotePalette = <Color>[
  Color(0xFFFFF9B1), // Miro Signature Yellow
  Color(0xFFD5F692), // Miro Light Green
  Color(0xFFD5F3FE), // Miro Light Blue
  Color(0xFFFFD0A8), // Miro Peach / Orange
  Color(0xFFFFCEE0), // Miro Pastel Pink
  Color(0xFFE1C4FE), // Miro Soft Purple
  Color(0xFFFFFFFF), // Pure White Note
  Color(0xFFE2E8F0), // Subtle Gray Note
];

/// Miro-style floating toolbar supporting selection, pen, shapes, sticky notes, text, and ER diagrams.
class BoardToolbar extends ConsumerWidget {
  const BoardToolbar({
    super.key,
    required this.vertical,
    required this.readOnly,
  });

  final bool vertical;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boardProvider);
    final board = ref.read(boardProvider.notifier);

    Widget tool(
      BoardTool t,
      IconData icon,
      String label, {
      Color? badgeColor,
    }) => _ToolButton(
      icon: icon,
      tooltip: label,
      selected: state.tool == t,
      badgeColor: badgeColor,
      onPressed: () => board.setTool(t),
    );

    final divider = vertical
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              width: 24,
              child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
            ),
          )
        : const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              height: 24,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFE5E7EB),
              ),
            ),
          );

    final hasSelection = state.selectedObjectId != null;

    final children = readOnly
        ? <Widget>[
            const _ToolButton(
              icon: Icons.pan_tool_alt_outlined,
              tooltip: 'Pan Canvas',
              selected: true,
            ),
          ]
        : <Widget>[
            tool(BoardTool.select, Icons.near_me_outlined, 'Select & Move (V)'),
            tool(
              BoardTool.pen,
              Icons.edit_outlined,
              'Pen (P)',
              badgeColor: state.color,
            ),
            tool(
              BoardTool.highlighter,
              Icons.border_color_outlined,
              'Highlighter (H)',
            ),
            tool(
              BoardTool.eraser,
              Icons.auto_fix_normal_outlined,
              'Eraser (E)',
            ),
            divider,
            _ShapesMenuButton(activeTool: state.tool, onSelect: board.setTool),
            _EngineeringMenuButton(
              activeTool: state.tool,
              onSelect: board.setTool,
              onInsertTemplate: (tpl) => board.insertErTemplate(tpl),
            ),
            tool(
              BoardTool.stickyNote,
              Icons.note_alt_outlined,
              'Sticky Note (N)',
              badgeColor: state.noteColor,
            ),
            tool(BoardTool.text, Icons.title, 'Text (T)'),
            tool(BoardTool.mapPin, Icons.location_on_outlined, 'Map Pin'),
            tool(BoardTool.hand, Icons.pan_tool_alt_outlined, 'Pan (Space)'),
            divider,
            _ColorButton(
              color: state.color,
              onPressed: () => _showStyleSheet(context),
            ),
            if (hasSelection) ...[
              divider,
              if (canEditObjectText(state.selectedObject))
                _ToolButton(
                  icon: Icons.edit_note,
                  tooltip: 'Edit Text / Note (Double-tap)',
                  onPressed: () {
                    final sel = state.selectedObject;
                    if (sel != null) {
                      showEditObjectTextDialog(context, ref, sel);
                    }
                  },
                ),
              _ToolButton(
                icon: Icons.copy,
                tooltip: 'Duplicate (Ctrl+D)',
                onPressed: board.duplicateSelected,
              ),
              _ToolButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete (Del)',
                onPressed: board.deleteSelected,
              ),
            ],
            divider,
            _ToolButton(
              icon: Icons.undo,
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: state.canUndo ? board.undo : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              tooltip: 'Redo (Ctrl+Y)',
              onPressed: state.canRedo ? board.redo : null,
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  void _showStyleSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _StyleSheet(),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.badgeColor,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color? badgeColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEBF5FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: !isEnabled
                  ? const Color(0xFFD1D5DB)
                  : (selected
                        ? const Color(0xFF0D54FF)
                        : const Color(0xFF374151)),
            ),
            if (badgeColor != null)
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ShapesMenuButton extends StatelessWidget {
  const _ShapesMenuButton({required this.activeTool, required this.onSelect});

  final BoardTool activeTool;
  final ValueChanged<BoardTool> onSelect;

  bool get isShapeActive =>
      activeTool == BoardTool.rectangle ||
      activeTool == BoardTool.circle ||
      activeTool == BoardTool.arrow ||
      activeTool == BoardTool.line ||
      activeTool == BoardTool.triangle ||
      activeTool == BoardTool.diamond ||
      activeTool == BoardTool.star ||
      activeTool == BoardTool.hexagon ||
      activeTool == BoardTool.parallelogram ||
      activeTool == BoardTool.cylinder ||
      activeTool == BoardTool.cloud;

  IconData get currentIcon => switch (activeTool) {
    BoardTool.circle => Icons.circle_outlined,
    BoardTool.arrow => Icons.arrow_outward,
    BoardTool.line => Icons.horizontal_rule,
    BoardTool.triangle => Icons.change_history,
    BoardTool.diamond => Icons.diamond_outlined,
    BoardTool.star => Icons.star_border,
    BoardTool.hexagon => Icons.hexagon_outlined,
    BoardTool.parallelogram => Icons.rectangle_outlined,
    BoardTool.cylinder => Icons.storage,
    BoardTool.cloud => Icons.cloud_outlined,
    _ => Icons.crop_square_sharp,
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<BoardTool>(
      tooltip: 'Shapes',
      icon: Icon(
        currentIcon,
        color: isShapeActive ? Theme.of(context).colorScheme.primary : null,
      ),
      onSelected: onSelect,
      itemBuilder: (_) => const [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'BASIC SHAPES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        PopupMenuItem(
          value: BoardTool.rectangle,
          child: ListTile(
            leading: Icon(Icons.crop_square_sharp),
            title: Text('Rectangle'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.circle,
          child: ListTile(
            leading: Icon(Icons.circle_outlined),
            title: Text('Circle'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.arrow,
          child: ListTile(
            leading: Icon(Icons.arrow_outward),
            title: Text('Arrow'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.line,
          child: ListTile(
            leading: Icon(Icons.horizontal_rule),
            title: Text('Line'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(
            'FLOWCHART & ARCHITECTURE SHAPES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        PopupMenuItem(
          value: BoardTool.triangle,
          child: ListTile(
            leading: Icon(Icons.change_history),
            title: Text('Triangle'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.diamond,
          child: ListTile(
            leading: Icon(Icons.diamond_outlined),
            title: Text('Diamond (Decision)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.parallelogram,
          child: ListTile(
            leading: Icon(Icons.rectangle_outlined),
            title: Text('Parallelogram (Input / Output)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.hexagon,
          child: ListTile(
            leading: Icon(Icons.hexagon_outlined),
            title: Text('Hexagon (Preparation / Service)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.cylinder,
          child: ListTile(
            leading: Icon(Icons.storage),
            title: Text('Cylinder (Database / Storage)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.cloud,
          child: ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Cloud (Cloud Service / Network)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: BoardTool.star,
          child: ListTile(
            leading: Icon(Icons.star_border),
            title: Text('Star (Feature / Milestone)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _EngineeringMenuButton extends StatelessWidget {
  const _EngineeringMenuButton({
    required this.activeTool,
    required this.onSelect,
    required this.onInsertTemplate,
  });

  final BoardTool activeTool;
  final ValueChanged<BoardTool> onSelect;
  final void Function(String templateName) onInsertTemplate;

  bool get isErActive =>
      activeTool == BoardTool.erTable || activeTool == BoardTool.erRelationship;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Engineering & ER Diagrams',
      icon: Icon(
        Icons.schema_outlined,
        color: isErActive ? scheme.primary : null,
      ),
      onSelected: (val) {
        switch (val) {
          case 'table':
            onSelect(BoardTool.erTable);
          case 'rel':
            onSelect(BoardTool.erRelationship);
          case 'tpl_ecommerce':
            onInsertTemplate('E-Commerce Schema');
          case 'tpl_auth':
            onInsertTemplate('Auth & Roles');
          case 'tpl_microservices':
            onInsertTemplate('Microservices Flow');
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'ENGINEERING TOOLS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'table',
          child: ListTile(
            leading: Icon(Icons.table_chart, color: Color(0xFF2563EB)),
            title: Text('ER Database Table'),
            subtitle: Text('Entity with PK/FK/Columns'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'rel',
          child: ListTile(
            leading: Icon(Icons.linear_scale, color: Color(0xFF059669)),
            title: Text('Crow\'s Foot Relationship'),
            subtitle: Text('1..N connector line'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(
            'DIAGRAM TEMPLATES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'tpl_ecommerce',
          child: ListTile(
            leading: Icon(
              Icons.shopping_bag_outlined,
              color: Colors.blueAccent,
            ),
            title: Text('E-Commerce Schema'),
            subtitle: Text('4 linked tables (users, orders, etc.)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'tpl_auth',
          child: ListTile(
            leading: Icon(Icons.security, color: Colors.purpleAccent),
            title: Text('Auth & Roles Schema'),
            subtitle: Text('RBAC accounts, roles, mappings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'tpl_microservices',
          child: ListTile(
            leading: Icon(Icons.cloud_sync_outlined, color: Colors.amber),
            title: Text('Microservices Flow'),
            subtitle: Text('Gateway, Service, Database flow'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.color, required this.onPressed});

  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Color & size',
      onPressed: onPressed,
      icon: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _StyleSheet extends ConsumerWidget {
  const _StyleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boardProvider);
    final board = ref.read(boardProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in kPalette)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => board.setColor(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == state.color
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: c == state.color ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Sticky Note Color',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                for (final c in kStickyNotePalette)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => board.setNoteColor(c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == state.noteColor
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: c == state.noteColor ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Stroke Width  ${state.width.round()}px',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              value: state.width,
              min: 1,
              max: 32,
              divisions: 31,
              label: state.width.round().toString(),
              onChanged: board.setWidth,
            ),
          ],
        ),
      ),
    );
  }
}
