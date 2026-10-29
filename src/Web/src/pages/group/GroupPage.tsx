// One group definition: the form for admins, the reader view for readers.
import { useParams } from 'react-router-dom';
import { Spinner } from '@fluentui/react-components';
import { useDefinition, useSettings } from '../../api/hooks';
import { ApiError } from '../../api/client';
import { useSession } from '../../auth/session';
import { AppLink } from '../../components/AppLink';
import { Section } from '../../components/ui';
import { ErrorView } from '../ErrorPages';
import { t } from '../../strings/en';
import { GroupForm } from './GroupForm';
import { ReaderView } from './ReaderView';

export function GroupPage() {
  const { id } = useParams();
  const { isAdmin } = useSession();
  const definition = useDefinition(id);
  const settings = useSettings();

  if (id && definition.isPending) return <Spinner label={t.app.loading} />;
  if (id && definition.error) {
    if (definition.error instanceof ApiError && definition.error.status === 404) {
      return (
        <Section>
          <p>{t.group.notFound}</p>
          <AppLink to="/">{t.error.backToGroups}</AppLink>
        </Section>
      );
    }
    return <ErrorView error={definition.error} onRetry={() => void definition.refetch()} />;
  }
  if (!isAdmin) {
    if (!definition.data)
      return <ErrorView error={new ApiError(403, { type: 'about:blank', title: t.denied.adminOnly, status: 403, correlationId: '' })} />;
    return <ReaderView definition={definition.data} />;
  }
  if (!id && settings.isPending) return <Spinner label={t.app.loading} />;
  return <GroupForm key={id ?? 'new'} definition={definition.data} settings={settings.data} />;
}
