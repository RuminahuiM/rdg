// A react-router link that looks like a Fluent link.
import { Link as RouterLink, type LinkProps } from 'react-router-dom';
import { makeStyles, mergeClasses, tokens } from '@fluentui/react-components';

const useStyles = makeStyles({
  link: {
    color: tokens.colorBrandForegroundLink,
    textDecoration: 'none',
    ':hover': { textDecoration: 'underline', color: tokens.colorBrandForegroundLinkHover },
    ':focus-visible': { outlineWidth: '2px', outlineStyle: 'solid', outlineColor: tokens.colorStrokeFocus2, borderRadius: '2px' },
  },
  strong: { fontWeight: tokens.fontWeightSemibold },
});

export function AppLink({ strong, className, ...props }: LinkProps & { strong?: boolean }) {
  const s = useStyles();
  return <RouterLink {...props} className={mergeClasses(s.link, strong && s.strong, className)} />;
}
